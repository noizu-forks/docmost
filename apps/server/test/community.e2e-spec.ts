import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { AppModule } from '../src/app.module';
import { ApiKeyService } from '../src/community/api-key/api-key.service';
import { UserRepo } from '@docmost/db/repos/user/user.repo';
import { WorkspaceRepo } from '@docmost/db/repos/workspace/workspace.repo';
import { PageRepo } from '@docmost/db/repos/page/page.repo';
import { SpaceRepo } from '@docmost/db/repos/space/space.repo';

/**
 * Community API e2e: mints an API key (via ApiKeyService, since there is no
 * programmatic login) and then drives the core client contract over HTTP
 * with `Authorization: Bearer <token>`.
 *
 * Requires a reachable database/redis; skipped unless DATABASE_URL and
 * COMMUNITY_E2E_USER_ID / COMMUNITY_E2E_WORKSPACE_ID are provided.
 */
const TEST_ENV_READY = !!(
  process.env.DATABASE_URL &&
  process.env.COMMUNITY_E2E_USER_ID &&
  process.env.COMMUNITY_E2E_WORKSPACE_ID
);

(TEST_ENV_READY ? describe : describe.skip)('Community API (e2e)', () => {
  let app: INestApplication;
  let apiKeyId: string;
  let pageId: string;

  const userId = process.env.COMMUNITY_E2E_USER_ID;
  const workspaceId = process.env.COMMUNITY_E2E_WORKSPACE_ID;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.setGlobalPrefix('api');
    await app.init();

    const user = await app.get(UserRepo).findById(userId, workspaceId);
    expect(user).toBeDefined();

    const minted = await app
      .get(ApiKeyService)
      .createApiKey({ name: 'community-e2e' }, user, workspaceId);
    apiKeyId = minted.id;
  });

  afterAll(async () => {
    if (apiKeyId) {
      await app
        .get(ApiKeyService)
        .revokeApiKey(apiKeyId, workspaceId)
        .catch(() => undefined);
    }
    if (pageId) {
      await app.get(PageRepo).deletePage(pageId).catch(() => undefined);
    }
    await app?.close();
  });

  const bearerAuth = (token: string) => ({
    Authorization: `Bearer ${token}`,
  });

  it('rejects requests without a token', async () => {
    await request(app.getHttpServer()).post('/api/keys/').expect(403);
  });

  it('lists API keys', async () => {
    const minted = await app
      .get(ApiKeyService)
      .createApiKey(
        { name: 'community-e2e-list' },
        await app.get(UserRepo).findById(userId, workspaceId),
        workspaceId,
      );

    const res = await request(app.getHttpServer())
      .get('/api/keys/')
      .set(bearerAuth(minted.token))
      .expect(200);

    expect(res.body.items.some((key: any) => key.id === minted.id)).toBe(true);
  });

  it('creates a page and drives the page-permission contract', async () => {
    const user = await app.get(UserRepo).findById(userId, workspaceId);
    const minted = await app
      .get(ApiKeyService)
      .createApiKey({ name: 'community-e2e-pages' }, user, workspaceId);

    const spaceRepo = app.get(SpaceRepo);
    const spaces = await spaceRepo.getSpacesInWorkspace(workspaceId, {
      limit: 1,
    });
    expect(spaces.items.length).toBeGreaterThan(0);

    const pageRepo = app.get(PageRepo);
    const page = await pageRepo.insertPage({
      title: 'community-e2e',
      workspaceId,
      spaceId: spaces.items[0].id,
      creatorId: userId,
      lastUpdatedById: userId,
    });
    pageId = page.id;

    await request(app.getHttpServer())
      .post('/api/pages/permission-info')
      .set(bearerAuth(minted.token))
      .send({ pageId })
      .expect(200)
      .expect((res) => {
        expect(res.body.hasDirectRestriction).toBe(false);
        expect(res.body.canAccess).toBe(true);
      });

    await request(app.getHttpServer())
      .post('/api/pages/restrict')
      .set(bearerAuth(minted.token))
      .send({ pageId })
      .expect(200);

    await request(app.getHttpServer())
      .post('/api/pages/add-permission')
      .set(bearerAuth(minted.token))
      .send({ pageId, role: 'writer', userIds: [userId] })
      .expect(200);

    await request(app.getHttpServer())
      .post('/api/pages/permissions')
      .set(bearerAuth(minted.token))
      .send({ pageId, limit: 20 })
      .expect(200)
      .expect((res) => {
        expect(res.body.permissions).toEqual([
          { type: 'user', id: userId, role: 'writer' },
        ]);
        expect(res.body.meta.nextCursor).toBeNull();
      });

    await request(app.getHttpServer())
      .post('/api/pages/update-permission')
      .set(bearerAuth(minted.token))
      .send({ pageId, userId, role: 'reader' })
      .expect(200);

    await request(app.getHttpServer())
      .post('/api/pages/remove-permission')
      .set(bearerAuth(minted.token))
      .send({ pageId, userIds: [userId] })
      .expect(200);

    await request(app.getHttpServer())
      .post('/api/pages/remove-restriction')
      .set(bearerAuth(minted.token))
      .send({ pageId })
      .expect(200);
  });

  it('invalidates a revoked key', async () => {
    const user = await app.get(UserRepo).findById(userId, workspaceId);
    const minted = await app
      .get(ApiKeyService)
      .createApiKey({ name: 'community-e2e-revoke' }, user, workspaceId);

    await request(app.getHttpServer())
      .get('/api/keys/')
      .set(bearerAuth(minted.token))
      .expect(200);

    await app.get(ApiKeyService).revokeApiKey(minted.id, workspaceId);

    await request(app.getHttpServer())
      .get('/api/keys/')
      .set(bearerAuth(minted.token))
      .expect(401);
  });
});
