import { UnauthorizedException } from '@nestjs/common';
import { JwtApiKeyPayload, JwtType } from '../../core/auth/dto/jwt-payload';
import { ApiKeyService } from './api-key.service';

function createDb(apiKey: any) {
  return {
    selectFrom: jest.fn().mockReturnThis(),
    where: jest.fn().mockReturnThis(),
    selectAll: jest.fn().mockReturnThis(),
    executeTakeFirst: jest.fn().mockResolvedValue(apiKey),
    updateTable: jest.fn().mockReturnThis(),
    set: jest.fn().mockReturnThis(),
    execute: jest.fn().mockResolvedValue(undefined),
  } as any;
}

function createUserRepo(user: any) {
  return { findById: jest.fn().mockResolvedValue(user) } as any;
}

function createWorkspaceRepo(workspace: any) {
  return { findById: jest.fn().mockResolvedValue(workspace) } as any;
}

function createService(db: any, user: any, workspace: any) {
  const userRepo = createUserRepo(user);
  const workspaceRepo = createWorkspaceRepo(workspace);
  const service = new ApiKeyService(
    db,
    { generateApiToken: jest.fn().mockResolvedValue('token') } as any,
    userRepo,
    workspaceRepo,
  );
  return { service, userRepo, workspaceRepo, db };
}

function payload(overrides: Partial<JwtApiKeyPayload> = {}): JwtApiKeyPayload {
  return {
    sub: 'user_1',
    apiKeyId: 'key_1',
    workspaceId: 'ws_1',
    type: JwtType.API_KEY,
    ...overrides,
  };
}

describe('ApiKeyService.validateApiKey', () => {
  const activeKey = {
    id: 'key_1',
    name: 'ci',
    workspaceId: 'ws_1',
    deletedAt: null,
    expiresAt: null,
  };
  const user = { id: 'user_1', deactivatedAt: null, deletedAt: null };
  const workspace = { id: 'ws_1' };

  it('returns the user and workspace for a valid key', async () => {
    const db = createDb(activeKey);
    const { service } = createService(db, user, workspace);

    const result = await service.validateApiKey(payload());

    expect(result).toEqual({ user, workspace });
  });

  it('rejects an unknown key', async () => {
    const db = createDb(undefined);
    const { service } = createService(db, user, workspace);

    await expect(service.validateApiKey(payload())).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects a revoked (soft-deleted) key', async () => {
    const db = createDb({ ...activeKey, deletedAt: new Date() });
    const { service } = createService(db, user, workspace);

    await expect(service.validateApiKey(payload())).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects an expired key', async () => {
    const db = createDb({
      ...activeKey,
      expiresAt: new Date(Date.now() - 1000),
    });
    const { service } = createService(db, user, workspace);

    await expect(service.validateApiKey(payload())).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects when the workspace is missing', async () => {
    const db = createDb(activeKey);
    const { service } = createService(db, user, null);

    await expect(service.validateApiKey(payload())).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects a disabled user', async () => {
    const db = createDb(activeKey);
    const { service } = createService(db, { ...user, deactivatedAt: new Date() }, workspace);

    await expect(service.validateApiKey(payload())).rejects.toThrow(
      UnauthorizedException,
    );
  });
});
