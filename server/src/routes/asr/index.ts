import { eq } from "drizzle-orm";
import { Hono } from "hono";
import { createMiddleware } from "hono/factory";
import { experimental_transcribe as transcribe } from "ai";
import { groq, type GroqTranscriptionModelOptions } from "@ai-sdk/groq";

import { db } from "../../db/client";
import { aiModelUsages, users } from "../../db/schema";
import { firebaseAuth } from "../../lib/firebase-admin";

type AuthUser = {
  id: string;
  firebaseUid: string;
  email: string;
  displayName: string | null;
};

type Variables = {
  authUser: AuthUser;
};

const authMiddleware = createMiddleware<{ Variables: Variables }>(async (c, next) => {
  const authHeader = c.req.header("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return c.json({ error: "Missing bearer token" }, 401);
  }

  const idToken = authHeader.slice("Bearer ".length).trim();

  try {
    const decoded = await firebaseAuth.verifyIdToken(idToken);
    const email = decoded.email;
    if (!email) {
      return c.json({ error: "Firebase token missing email" }, 401);
    }

    const upserted = await db
      .insert(users)
      .values({
        firebaseUid: decoded.uid,
        email,
        displayName: decoded.name ?? null,
      })
      .onConflictDoUpdate({
        target: users.firebaseUid,
        set: {
          email,
          displayName: decoded.name ?? null,
          updatedAt: new Date(),
        },
      })
      .returning({
        id: users.id,
        firebaseUid: users.firebaseUid,
        email: users.email,
        displayName: users.displayName,
      });

    const authUser = upserted[0];
    if (!authUser) {
      const fallback = await db
        .select({
          id: users.id,
          firebaseUid: users.firebaseUid,
          email: users.email,
          displayName: users.displayName,
        })
        .from(users)
        .where(eq(users.firebaseUid, decoded.uid))
        .limit(1);

      if (!fallback[0]) {
        return c.json({ error: "Unable to load authenticated user" }, 500);
      }

      c.set("authUser", fallback[0]);
      await next();
      return;
    }

    c.set("authUser", authUser);
    await next();
  } catch {
    return c.json({ error: "Invalid Firebase token" }, 401);
  }
});

type TranscriptionSegment = {
  text: string;
  start: number;
  end: number;
};

type TranscriptionWord = {
  word: string;
  start: number;
  end: number;
  confidence: number;
};

type TranscriptionResponse = {
  text: string;
  segments: TranscriptionSegment[];
  words?: TranscriptionWord[];
  language: string;
  duration: number;
};

const asrRouter = new Hono<{ Variables: Variables }>();

asrRouter.use("/transcribe", authMiddleware);

asrRouter.post("/transcribe", async (c) => {
  const user = c.get("authUser");
  const formData = await c.req.formData();
  const audioFile = formData.get("audio") as File | null;

  if (!audioFile) {
    return c.json({ error: "Audio file is required" }, 400);
  }

  const allowedTypes = [
    "audio/mpeg",
    "audio/mp3",
    "audio/wav",
    "audio/ogg",
    "audio/webm",
    "audio/m4a",
    "audio/x-m4a",
    "audio/aac",
  ];

  if (!allowedTypes.includes(audioFile.type)) {
    return c.json(
      {
        error: "Invalid audio file type",
        details: `Received: ${audioFile.type}. Allowed: ${allowedTypes.join(", ")}`,
      },
      400,
    );
  }

  const language = formData.get("language") as string | null;
  const durationMsParam = (formData.get("durationMs") ?? formData.get("duration")) as string | null;
  const clientDurationMs = durationMsParam ? parseFloat(durationMsParam) : null;

  const arrayBuffer = await audioFile.arrayBuffer();
  const buffer = Buffer.from(arrayBuffer);

  const providerOptions: GroqTranscriptionModelOptions = {};

  if (language) {
    providerOptions.language = language;
  }

  providerOptions.responseFormat = "verbose_json";
  providerOptions.timestampGranularities = ["segment", "word"];

  const startTime = Date.now();

  try {
    const result = await transcribe({
      model: groq.transcription("whisper-large-v3-turbo"),
      audio: buffer,
      providerOptions: {
        groq: providerOptions,
      },
    });

    const processingTimeMs = Date.now() - startTime;

    const response: TranscriptionResponse = {
      text: result.text,
      segments:
        result.segments?.map((seg) => ({
          text: seg.text,
          start: seg.startSecond,
          end: seg.endSecond,
        })) ?? [],
      language: providerOptions.language ?? "auto",
      duration: typeof clientDurationMs === "number" && Number.isFinite(clientDurationMs)
        ? clientDurationMs / 1000
        : ("duration" in result && typeof result.duration === "number"
          ? result.duration
          : 0),
    };

    if (result.segments) {
      const words: TranscriptionWord[] = [];
      for (const seg of result.segments) {
        if (seg && "words" in seg && Array.isArray((seg as Record<string, unknown>).words)) {
          const segWords = (seg as Record<string, unknown>).words as Array<{
            word: string;
            startSecond: number;
            endSecond: number;
            confidence?: number;
          }>;
          for (const w of segWords) {
            words.push({
              word: w.word,
              start: w.startSecond,
              end: w.endSecond,
              confidence: w.confidence ?? 1,
            });
          }
        }
      }
      if (words.length > 0) {
        response.words = words;
      }
    }

    let inputTokens: number | null = null;
    let outputTokens: number | null = null;
    const resultAny = result as unknown as Record<string, unknown>;
    const usage = resultAny.usage;
    if (usage && typeof usage === "object") {
      const u = usage as Record<string, unknown>;
      inputTokens = typeof u.inputTokens === "number" ? u.inputTokens : null;
      outputTokens = typeof u.outputTokens === "number" ? u.outputTokens : null;
    }

    await db.insert(aiModelUsages).values({
      userId: user.id,
      type: "asr",
      modelProvider: "groq",
      modelId: "whisper-large-v3-turbo",
      inputTokens,
      outputTokens,
      processingTimeMs,
      metadata: JSON.stringify({
        language: language ?? undefined,
        audioDuration: response.duration,
      }),
    });

    return c.json(response);
  } catch (error) {
    console.error("Transcription error:", error);
    return c.json(
      {
        error: "Transcription failed",
        details: error instanceof Error ? error.message : "Unknown error",
      },
      500,
    );
  }
});

export default asrRouter;
