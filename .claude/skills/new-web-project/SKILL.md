---
name: new-web-project
description: Scaffold a new web project. Stack is always SvelteKit 5 + Tailwind v4 + Drizzle ORM + PostgreSQL + adapter-node. Auth (session-cookie + Argon2) is optional. Homelab deployment (Dockerfile, CI, K8s manifests) is always included at the end. Use when creating a new app, starting a new project, or setting up a new web service.
---

## Stack

| Layer | Choice | Notes |
|---|---|---|
| Framework | SvelteKit 2 + Svelte 5 (runes) | `@sveltejs/adapter-node`, TypeScript |
| CSS | Tailwind v4 | via `@tailwindcss/vite` — no `tailwind.config.js` needed |
| ORM | Drizzle ORM + drizzle-kit | `postgres-js` driver |
| Database | PostgreSQL | Connection via `DATABASE_URL` env var |
| Auth | Session-cookie + Argon2 | `@node-rs/argon2`, `@oslojs/*` — **only when asked** |
| Linting | ESLint + Prettier + prettier-plugin-svelte + prettier-plugin-tailwindcss | |
| Deployment | adapter-node → Docker → ghcr.io → ArgoCD | See homelab step at end |

---

## Step 1 — Gather inputs

Ask the user:
1. **Project name** (slug: lowercase, hyphens OK) — used everywhere
2. **Does it need authentication?** (yes/no)

Infer from context where obvious.

---

## Step 2 — Create the SvelteKit project

Run in `E:\Koder\`:

```powershell
cd E:\Koder
npx sv create {NAME}
```

When prompted, select:
- **Template**: Skeleton project
- **Type checking**: TypeScript
- **Add ESLint**: yes
- **Add Prettier**: yes
- **Add Playwright**: no
- **Add Vitest**: no

Then enter the project:

```powershell
cd E:\Koder\{NAME}
```

---

## Step 3 — Install dependencies

```powershell
npm install drizzle-orm postgres @oslojs/crypto @oslojs/encoding
npm install -D @tailwindcss/vite tailwindcss drizzle-kit @sveltejs/adapter-node prettier-plugin-tailwindcss prettier-plugin-svelte
```

If auth is needed, also install:

```powershell
npm install @node-rs/argon2
```

---

## Step 4 — Configure adapter and Tailwind

**`svelte.config.js`** — replace entirely:

```js
import adapter from '@sveltejs/adapter-node';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

const config = {
	preprocess: vitePreprocess(),
	kit: {
		adapter: adapter()
	}
};

export default config;
```

**`vite.config.ts`** — replace entirely:

```ts
import tailwindcss from '@tailwindcss/vite';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [tailwindcss(), sveltekit()]
});
```

**`src/app.css`** — replace entirely:

```css
@import 'tailwindcss';
```

**`src/routes/+layout.svelte`** — make sure it imports `app.css`:

```svelte
<script lang="ts">
	import '../app.css';
	let { children } = $props();
</script>

{@render children()}
```

**`.prettierrc`** — replace entirely:

```json
{
	"useTabs": true,
	"singleQuote": true,
	"trailingComma": "none",
	"printWidth": 100,
	"plugins": ["prettier-plugin-svelte", "prettier-plugin-tailwindcss"],
	"overrides": [{ "files": "*.svelte", "options": { "parser": "svelte" } }]
}
```

---

## Step 5 — Configure Drizzle and database

**`drizzle.config.ts`** (create at project root):

```ts
import { defineConfig } from 'drizzle-kit';
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is not set');

export default defineConfig({
	schema: './src/lib/server/db/schema.ts',
	dbCredentials: {
		url: process.env.DATABASE_URL
	},
	verbose: true,
	strict: true,
	dialect: 'postgresql'
});
```

**`src/lib/server/db/index.ts`** (create, including parent dirs):

```ts
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema';
import { env } from '$env/dynamic/private';
if (!env.DATABASE_URL) throw new Error('DATABASE_URL is not set');

const client = postgres(env.DATABASE_URL);

export const db = drizzle(client, { schema });
```

**`src/lib/server/db/schema.ts`**:

```ts
import { pgTable, text, serial, timestamp } from 'drizzle-orm/pg-core';

// Add your tables here
```

If auth is needed, add `user` and `session` tables (see Step 6).

**Add db scripts to `package.json`** (merge into existing `scripts`):

```json
"db:push": "drizzle-kit push",
"db:migrate": "drizzle-kit migrate",
"db:studio": "drizzle-kit studio"
```

**`.env`** (create, never commit):

```
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/{NAME}
```

**`.env.example`** (create, commit this):

```
DATABASE_URL=postgresql://user:password@host:5432/{NAME}
```

Add `.env` to `.gitignore` if not already there.

---

## Step 6 — Auth (only if requested)

**`src/lib/server/auth.ts`**:

```ts
import type { RequestEvent } from '@sveltejs/kit';
import { eq } from 'drizzle-orm';
import { sha256 } from '@oslojs/crypto/sha2';
import { encodeBase64url, encodeHexLowerCase } from '@oslojs/encoding';
import { db } from '$lib/server/db';
import * as table from '$lib/server/db/schema';

const DAY_IN_MS = 1000 * 60 * 60 * 24;

export const sessionCookieName = 'auth-session';

export function generateSessionToken() {
	const bytes = crypto.getRandomValues(new Uint8Array(18));
	return encodeBase64url(bytes);
}

export async function createSession(token: string, userId: string) {
	const sessionId = encodeHexLowerCase(sha256(new TextEncoder().encode(token)));
	const session: table.Session = {
		id: sessionId,
		userId,
		expiresAt: new Date(Date.now() + DAY_IN_MS * 30)
	};
	await db.insert(table.session).values(session);
	return session;
}

export async function validateSessionToken(token: string) {
	const sessionId = encodeHexLowerCase(sha256(new TextEncoder().encode(token)));
	const [result] = await db
		.select({
			user: { id: table.user.id, username: table.user.username },
			session: table.session
		})
		.from(table.session)
		.innerJoin(table.user, eq(table.session.userId, table.user.id))
		.where(eq(table.session.id, sessionId));

	if (!result) return { session: null, user: null };

	const { session, user } = result;
	if (Date.now() >= session.expiresAt.getTime()) {
		await db.delete(table.session).where(eq(table.session.id, session.id));
		return { session: null, user: null };
	}

	if (Date.now() >= session.expiresAt.getTime() - DAY_IN_MS * 15) {
		session.expiresAt = new Date(Date.now() + DAY_IN_MS * 30);
		await db.update(table.session).set({ expiresAt: session.expiresAt }).where(eq(table.session.id, session.id));
	}

	return { session, user };
}

export type SessionValidationResult = Awaited<ReturnType<typeof validateSessionToken>>;

export async function invalidateSession(sessionId: string) {
	await db.delete(table.session).where(eq(table.session.id, sessionId));
}

export function setSessionTokenCookie(event: RequestEvent, token: string, expiresAt: Date) {
	event.cookies.set(sessionCookieName, token, {
		expires: expiresAt,
		path: '/',
		sameSite: 'lax',
		httpOnly: true,
		secure: true
	});
}

export function deleteSessionTokenCookie(event: RequestEvent) {
	event.cookies.delete(sessionCookieName, { path: '/' });
}
```

**`src/hooks.server.ts`**:

```ts
import { redirect, type Handle } from '@sveltejs/kit';
import * as auth from '$lib/server/auth.js';

const openRoutes = ['/', '/auth'];

const handleAuth: Handle = async ({ event, resolve }) => {
	const sessionToken = event.cookies.get(auth.sessionCookieName);

	if (!openRoutes.includes(event.url.pathname) && !sessionToken) {
		return redirect(302, '/auth');
	}

	if (!sessionToken) {
		event.locals.user = null;
		event.locals.session = null;
		return resolve(event);
	}

	const { session, user } = await auth.validateSessionToken(sessionToken);
	if (session) {
		auth.setSessionTokenCookie(event, sessionToken, session.expiresAt);
	} else {
		auth.deleteSessionTokenCookie(event);
	}

	event.locals.user = user;
	event.locals.session = session;
	return resolve(event);
};

export const handle: Handle = handleAuth;
```

**`src/app.d.ts`** — replace entirely:

```ts
declare global {
	namespace App {
		interface Locals {
			user: import('$lib/server/auth').SessionValidationResult['user'];
			session: import('$lib/server/auth').SessionValidationResult['session'];
		}
	}
}

export {};
```

**Add auth tables to `src/lib/server/db/schema.ts`**:

```ts
import { pgTable, text, serial, timestamp } from 'drizzle-orm/pg-core';

export const user = pgTable('user', {
	id: text('id').primaryKey(),
	username: text('username').notNull(),
	passwordHash: text('password_hash').notNull()
});

export const session = pgTable('session', {
	id: text('id').primaryKey(),
	userId: text('user_id').notNull().references(() => user.id),
	expiresAt: timestamp('expires_at').notNull()
});

export type Session = typeof session.$inferSelect;
export type User = typeof user.$inferSelect;
```

Password hashing in login/register actions uses `@node-rs/argon2` with these fixed params (keep them identical in both actions):

```ts
import { hash, verify } from '@node-rs/argon2';

const passwordHash = await hash(password, {
	memoryCost: 19456,
	timeCost: 2,
	outputLen: 32,
	parallelism: 1
});
```

---

## Step 7 — Health check route

Create `src/routes/health/+server.ts` (required by the Docker `HEALTHCHECK` and K8s probes):

```ts
import { json } from '@sveltejs/kit';

export function GET() {
	return json({ ok: true });
}
```

---

## Step 8 — Homelab deployment

Follow the `/new-homelab-project` skill to generate:
- `Dockerfile` + `Dockerfile.migrate` (if auth/DB)
- `.github/workflows/docker-publish.yml`
- `E:\Koder\homelab\applications\{NAME}/` manifests

Inputs for that skill:
- `NAME`: same slug as this project
- `PORT`: `3000`
- `SUBDOMAIN`: `{NAME}.erikak.no`
- `NEEDS_DB`: yes
- `NEEDS_MIGRATE`: yes (Drizzle)

---

## Conventions to follow in this project

- **Svelte 5 runes everywhere** — `$state`, `$props`, `$derived`, `$effect`. No legacy `export let` or stores.
- **Server-only DB access** — only import `$lib/server/*` from `.server.ts` files or `+server.ts` routes. Never from client components.
- **Tailwind theme tokens** — declare custom design tokens (`--color-*`, `--font-*`) inside `@theme {}` in `app.css`, not in a config file.
- **Single DB client** — the `db` export from `$lib/server/db/index.ts` is the only postgres connection. Do not create new ones.
- **Auth guard** — `hooks.server.ts` redirects unauthenticated page navigation; API routes (`+server.ts`) and form actions must still check `event.locals.user` themselves.
