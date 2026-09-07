import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { AppModule } from '../src/app.module';
import { ApiKeyService } from '../src/community/api-key/api-key.service';
import { UserRepo } from '@docmost/db/repos/user/user.repo';
import { WorkspaceRepo } from '@docmost/db/repos/workspace/workspace.repo';
import { PageRepo } from '@docmost/db/repos/page/page.repo';
import { SpaceRepo } from '@docmost/db/repos/space/space.repo';

/**
 * v1 e2e: mints an API key (via ApiKeyService, since there is no programmatic
 * login) and walks the v1 contract table over HTTP with Bearer auth:
 * keys, spaces, pages (create/get/patch/put-content), share upsert,
 * page access (restriction + grants), search, idempotent deletes.
 *
 * Requires a reachable database/redis; skipped unless DATABASE_URL and
 * COMMUNITY_E2E_USER_ID / COMMUNITY_E2E_WORKSPACE_ID are provided.
 */
const TEST_ENV_READY = !!(
  process.env.DATABASE_URL &&
  process.env.COMMUNITY_E2E_USER_ID &&
  process.env.COMMUNITY_E2E_WORKSPACE_ID
);

(TEST_ENV_READY ? describe : describe.skip)('Community API v1 (e2e)', () => {
  let app: INestApplication;
  let httpBase: string;
  let pageId: string;
  const createdKeyIds: string[] = [];

  const userId = process.env.COMMUNITY_E2E_USER_ID;
  const workspaceId = process.env.COMMUNITY_E2E_WORKSPACE_ID;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication<NestFastifyApplication>(
      new FastifyAdapter(),
    );
    app.setGlobalPrefix('api');
    await app.init();
    await app.listen(0);
    httpBase = `http://127.0.0.1:${(app.getHttpServer().address() as any).port}`;
  });

  afterAll(async () => {
    if (pageId) {
      await app.get(PageRepo).deletePage(pageId).catch(() => undefined);
    }
    for (const id of createdKeyIds) {
      await app.get(ApiKeyService).revokeApiKey(id, workspaceId).catch(() => undefined);
    }
    await app?.close();
  });

  const mintKey = async (name: string): Promise<string> => {
    const user = await app.get(UserRepo).findById(userId, workspaceId);
    const minted = await app
      .get(ApiKeyService)
      .createApiKey({ name }, user, workspaceId);
    createdKeyIds.push(minted.id);
    return minted.token;
  };

  it('rejects requests without a token (uniform error envelope)', async () => {
    const res = await request(httpBase).get('/api/v1/spaces');
    expect([401, 403]).toContain(res.status);
    expect(res.body.error).toMatchObject({
      code: expect.any(String),
      statusCode: expect.any(Number),
    });
  });

  it('lists and revokes API keys', async () => {
    const token = await mintKey('v1-e2e-keys');

    const list = await request(httpBase)
      .get('/api/v1/keys?limit=100')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(Array.isArray(list.body.data)).toBe(true);
    expect(
      list.body.data.some((key: any) => key.id === createdKeyIds[createdKeyIds.length - 1]),
    ).toBe(true);

    await request(httpBase)
      .delete(`/api/v1/keys/${createdKeyIds[createdKeyIds.length - 1]}`)
      .set('Authorization', `Bearer ${token}`)
      .expect(204);

    // idempotent
    // revoked key no longer authenticates — the key IS its own credential, so
    // replaying the delete with it now yields 401 (idempotency applies to the
    // resource being gone, not to revoked credentials)
    await request(httpBase)
      .get('/api/v1/spaces')
      .set('Authorization', `Bearer ${token}`)
      .expect(401);
  });

  it('walks the spaces + pages + share + access contract', async () => {
    const token = await mintKey('v1-e2e-flow');
    const auth = { Authorization: `Bearer ${token}` };
    const server = httpBase;

    // spaces list
    const spaces = await request(server)
      .get('/api/v1/spaces?limit=1')
      .set(auth)
      .expect(200);
    expect(spaces.body.data.length).toBeGreaterThan(0);
    const spaceId = spaces.body.data[0].id;

    // space info
    await request(server).get(`/api/v1/spaces/${spaceId}`).set(auth).expect(200);

    // create page (markdown-first)
    const created = await request(server)
      .post(`/api/v1/spaces/${spaceId}/pages`)
      .set(auth)
      .send({ title: 'v1-e2e', content: '# hello', parentId: undefined })
      .expect(201);
    pageId = created.body.id;

    // get page (default markdown content)
    const got = await request(server)
      .get(`/api/v1/pages/${pageId}?format=markdown&include=breadcrumbs`)
      .set(auth)
      .expect(200);
    // content passed at create time must be persisted (markdown default)
    expect(got.body.content).toContain('hello');
    expect(got.body.permissions).toMatchObject({ canEdit: expect.any(Boolean) });
    expect(Array.isArray(got.body.breadcrumbs)).toBe(true);

    // patch title
    await request(server)
      .patch(`/api/v1/pages/${pageId}`)
      .set(auth)
      .send({ title: 'v1-e2e-renamed' })
      .expect(200);

    // put content
    await request(server)
      .put(`/api/v1/pages/${pageId}/content`)
      .set(auth)
      .send({ content: 'appended', operation: 'append', format: 'markdown' })
      .expect(200);

    // share upsert then delete
    const shared = await request(server)
      .put(`/api/v1/pages/${pageId}/share`)
      .set(auth)
      .send({ shared: true, includeSubPages: false })
      .expect(200);
    expect(shared.body.shared).toBe(true);
    expect(shared.body.publicUrl).toContain('/share/');

    await request(server)
      .put(`/api/v1/pages/${pageId}/share`)
      .set(auth)
      .send({ shared: false })
      .expect(200);

    // access: restrict, grants, patch, delete, unrestrict
    await request(server)
      .put(`/api/v1/pages/${pageId}/access/restriction`)
      .set(auth)
      .send({ restricted: true })
      .expect(200);

    const grants = await request(server)
      .post(`/api/v1/pages/${pageId}/access/grants`)
      .set(auth)
      .send({ grants: [{ type: 'user', principalId: userId, role: 'writer' }] })
      .expect(201);
    const grantId = grants.body.data[0]?.id;
    expect(grantId).toBeDefined();

    const access = await request(server)
      .get(`/api/v1/pages/${pageId}/access?cursor=`)
      .set(auth)
      .expect(200);
    expect(access.body.restriction).toBe('direct');
    expect(access.body.grants.data.length).toBeGreaterThan(0);
    expect(access.body.grants.meta.nextCursor).toBeNull();

    await request(server)
      .patch(`/api/v1/pages/${pageId}/access/grants/${grantId}`)
      .set(auth)
      .send({ role: 'reader' })
      .expect(200);

    await request(server)
      .delete(`/api/v1/pages/${pageId}/access/grants/${grantId}`)
      .set(auth)
      .expect(204);

    await request(server)
      .delete(`/api/v1/pages/${pageId}/access/grants/${grantId}`)
      .set(auth)
      .expect(204); // idempotent

    await request(server)
      .put(`/api/v1/pages/${pageId}/access/restriction`)
      .set(auth)
      .send({ restricted: false })
      .expect(200);

    // search
    await request(server)
      .get('/api/v1/search?q=v1-e2e-renamed&limit=5')
      .set(auth)
      .expect(200)
      .expect((res) => {
        expect(Array.isArray(res.body.data)).toBe(true);
        expect(res.body.meta).toEqual({ nextCursor: null });
      });

    // children + breadcrumbs + list endpoints
    await request(server)
      .get(`/api/v1/pages/${pageId}/children`)
      .set(auth)
      .expect(200);
    await request(server)
      .get(`/api/v1/spaces/${spaceId}/pages`)
      .set(auth)
      .expect(200);

    // trash (idempotent 204)
    await request(server)
      .delete(`/api/v1/pages/${pageId}`)
      .set(auth)
      .expect(204);
    await request(server)
      .delete(`/api/v1/pages/${pageId}`)
      .set(auth)
      .expect(204);

    // restore
    await request(server)
      .post(`/api/v1/pages/${pageId}/restore`)
      .set(auth)
      .expect(201);
  });
});
