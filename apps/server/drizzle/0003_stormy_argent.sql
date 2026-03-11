ALTER TABLE "asr_transcription_requests" RENAME TO "ai_model_usages";--> statement-breakpoint
ALTER TABLE "ai_model_usages" DROP CONSTRAINT "asr_transcription_requests_user_id_users_id_fk";
--> statement-breakpoint
ALTER TABLE "ai_model_usages" ADD COLUMN "type" text NOT NULL;--> statement-breakpoint
ALTER TABLE "ai_model_usages" ADD COLUMN "model_provider" text NOT NULL;--> statement-breakpoint
ALTER TABLE "ai_model_usages" ADD COLUMN "model_id" text NOT NULL;--> statement-breakpoint
ALTER TABLE "ai_model_usages" ADD COLUMN "metadata" text;--> statement-breakpoint
ALTER TABLE "ai_model_usages" ADD CONSTRAINT "ai_model_usages_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ai_model_usages" DROP COLUMN "audio_file_name";--> statement-breakpoint
ALTER TABLE "ai_model_usages" DROP COLUMN "audio_file_size";--> statement-breakpoint
ALTER TABLE "ai_model_usages" DROP COLUMN "audio_duration";--> statement-breakpoint
ALTER TABLE "ai_model_usages" DROP COLUMN "language";--> statement-breakpoint
ALTER TABLE "ai_model_usages" DROP COLUMN "model";--> statement-breakpoint
ALTER TABLE "ai_model_usages" DROP COLUMN "prompt";--> statement-breakpoint
ALTER TABLE "ai_model_usages" DROP COLUMN "temperature";--> statement-breakpoint
ALTER TABLE "ai_model_usages" DROP COLUMN "timestamp_granularities";