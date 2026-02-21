CREATE TABLE "asr_transcription_requests" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"audio_file_name" text,
	"audio_file_size" integer,
	"audio_duration" integer,
	"language" text,
	"model" text NOT NULL,
	"prompt" text,
	"temperature" integer,
	"timestamp_granularities" text,
	"input_tokens" integer,
	"output_tokens" integer,
	"processing_time_ms" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "asr_transcription_requests" ADD CONSTRAINT "asr_transcription_requests_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;