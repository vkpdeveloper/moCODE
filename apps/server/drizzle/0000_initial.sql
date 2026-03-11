CREATE TABLE "users" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "firebase_uid" text NOT NULL,
  "email" text NOT NULL,
  "display_name" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE UNIQUE INDEX "users_firebase_uid_key" ON "users" USING btree ("firebase_uid");

CREATE TABLE "entitlements" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "one_time_unlocked" boolean DEFAULT false NOT NULL,
  "provider" text DEFAULT 'dodopayments' NOT NULL,
  "payment_id" text,
  "paid_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "entitlements_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade
);

CREATE UNIQUE INDEX "entitlements_user_id_key" ON "entitlements" USING btree ("user_id");

CREATE TABLE "checkout_sessions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "user_id" uuid NOT NULL,
  "dodo_session_id" text NOT NULL,
  "checkout_url" text NOT NULL,
  "product_id" text NOT NULL,
  "quantity" integer DEFAULT 1 NOT NULL,
  "status" text DEFAULT 'created' NOT NULL,
  "payment_id" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "checkout_sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE cascade
);

CREATE UNIQUE INDEX "checkout_sessions_dodo_session_id_key" ON "checkout_sessions" USING btree ("dodo_session_id");
