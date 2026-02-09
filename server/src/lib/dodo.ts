import { dodoApiBaseUrl, env } from './env';

export type CreateCheckoutSessionInput = {
  productId: string;
  quantity: number;
  customerEmail: string;
  customerName: string | null;
  returnUrl: string;
  metadata?: Record<string, string>;
};

export type CreateCheckoutSessionResponse = {
  session_id: string;
  checkout_url: string;
};

export async function createDodoCheckoutSession(
  input: CreateCheckoutSessionInput,
): Promise<CreateCheckoutSessionResponse> {
  const response = await fetch(`${dodoApiBaseUrl}/checkouts`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${env.DODO_PAYMENTS_API_KEY}`,
    },
    body: JSON.stringify({
      product_cart: [{ product_id: input.productId, quantity: input.quantity }],
      customer: {
        email: input.customerEmail,
        name: input.customerName ?? undefined,
      },
      return_url: input.returnUrl,
      feature_flags: {
        redirect_immediately: true,
      },
      metadata: input.metadata,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Dodo checkout session failed: ${response.status} ${errorText}`);
  }

  return (await response.json()) as CreateCheckoutSessionResponse;
}
