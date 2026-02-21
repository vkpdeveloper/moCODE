import {
  boolean,
  integer,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

export const users = pgTable(
  'users',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    firebaseUid: text('firebase_uid').notNull(),
    email: text('email').notNull(),
    displayName: text('display_name'),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [uniqueIndex('users_firebase_uid_key').on(table.firebaseUid)],
);

export const entitlements = pgTable(
  'entitlements',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    oneTimeUnlocked: boolean('one_time_unlocked').default(false).notNull(),
    provider: text('provider').default('dodopayments').notNull(),
    paymentId: text('payment_id'),
    paidAt: timestamp('paid_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [uniqueIndex('entitlements_user_id_key').on(table.userId)],
);

export const checkoutSessions = pgTable(
  'checkout_sessions',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    dodoSessionId: text('dodo_session_id').notNull(),
    checkoutUrl: text('checkout_url').notNull(),
    productId: text('product_id').notNull(),
    quantity: integer('quantity').default(1).notNull(),
    status: text('status').default('created').notNull(),
    paymentId: text('payment_id'),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [uniqueIndex('checkout_sessions_dodo_session_id_key').on(table.dodoSessionId)],
);

export const accountDeletionRequests = pgTable('account_deletion_requests', {
  id: uuid('id').defaultRandom().primaryKey(),
  email: text('email').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const earlyAccessEmails = pgTable('early_access_emails', {
  id: uuid('id').defaultRandom().primaryKey(),
  email: text('email').notNull().unique(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const aiModelUsages = pgTable(
  'ai_model_usages',
  {
    id: uuid('id').defaultRandom().primaryKey(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    type: text('type').notNull(),
    modelProvider: text('model_provider').notNull(),
    modelId: text('model_id').notNull(),
    inputTokens: integer('input_tokens'),
    outputTokens: integer('output_tokens'),
    processingTimeMs: integer('processing_time_ms'),
    metadata: text('metadata'),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  },
);
