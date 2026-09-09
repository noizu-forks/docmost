import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { JwtApiKeyPayload, JwtType } from '../../core/auth/dto/jwt-payload';
import { executeWithCursorPagination } from '@docmost/db/pagination/cursor-pagination';
import { API_KEY_DEFAULT_EXPIRES_IN, ApiKeyService } from './api-key.service';

jest.mock('@docmost/db/pagination/cursor-pagination', () => ({
  executeWithCursorPagination: jest.fn().mockResolvedValue({
    items: [{ id: 'key_1', name: 'ci' }],
    meta: { hasNextPage: true, nextCursor: 'cursor_2' },
  }),
}));

function createDb(apiKey: any) {
  return {
    selectFrom: jest.fn().mockReturnThis(),
    where: jest.fn().mockReturnThis(),
    selectAll: jest.fn().mockReturnThis(),
    executeTakeFirst: jest.fn().mockResolvedValue(apiKey),
    insertInto: jest.fn().mockReturnThis(),
    values: jest.fn().mockReturnThis(),
    returningAll: jest.fn().mockReturnThis(),
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
  const tokenService = {
    generateApiToken: jest.fn().mockResolvedValue('token'),
  } as any;
  const service = new ApiKeyService(db, tokenService, userRepo, workspaceRepo);
  return { service, userRepo, workspaceRepo, tokenService, db };
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
      'API key expired',
    );
  });

  it('accepts a key that expires in the future', async () => {
    const db = createDb({
      ...activeKey,
      expiresAt: new Date(Date.now() + 60_000),
    });
    const { service } = createService(db, user, workspace);

    await expect(service.validateApiKey(payload())).resolves.toEqual({
      user,
      workspace,
    });
  });

  it('rejects when the workspace is missing', async () => {
    const db = createDb(activeKey);
    const { service } = createService(db, user, null);

    await expect(service.validateApiKey(payload())).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects a missing user', async () => {
    const db = createDb(activeKey);
    const { service } = createService(db, null, workspace);

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

  it('rejects a deleted user', async () => {
    const db = createDb(activeKey);
    const { service } = createService(db, { ...user, deletedAt: new Date() }, workspace);

    await expect(service.validateApiKey(payload())).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('touches last_used_at after a successful validation', async () => {
    const db = createDb(activeKey);
    const { service } = createService(db, user, workspace);

    await service.validateApiKey(payload());
    // fire-and-forget: let the microtask queue drain
    await Promise.resolve();
    await Promise.resolve();

    expect(db.updateTable).toHaveBeenCalledWith('apiKeys');
    expect(db.set).toHaveBeenCalledWith(
      expect.objectContaining({ lastUsedAt: expect.any(Date) }),
    );
  });

  it('never fails auth when the last_used_at write errors', async () => {
    const db = createDb(activeKey);
    db.execute = jest.fn().mockRejectedValue(new Error('db down'));
    const { service } = createService(db, user, workspace);

    const result = await service.validateApiKey(payload());
    await db.execute.mock.results[0].value.catch(() => {});

    expect(result).toEqual({ user, workspace });
  });
});

describe('ApiKeyService.createApiKey', () => {
  const user = { id: 'user_1' } as any;
  const mintedKey = { id: 'key_1', name: 'ci', createdAt: new Date() };

  it('mints a key and returns the raw token exactly once', async () => {
    const db = createDb(mintedKey);
    const { service, tokenService } = createService(db, user, 'ws_1');

    const result = await service.createApiKey({ name: 'ci' }, user, 'ws_1');

    expect(db.insertInto).toHaveBeenCalledWith('apiKeys');
    expect(db.values).toHaveBeenCalledWith({
      name: 'ci',
      creatorId: 'user_1',
      workspaceId: 'ws_1',
    });
    expect(tokenService.generateApiToken).toHaveBeenCalledWith(
      expect.objectContaining({
        apiKeyId: 'key_1',
        user,
        workspaceId: 'ws_1',
        expiresIn: API_KEY_DEFAULT_EXPIRES_IN,
      }),
    );
    expect(result).toMatchObject({ id: 'key_1', name: 'ci', token: 'token' });
  });

  it('honours an explicit expiresIn from the DTO', async () => {
    const db = createDb(mintedKey);
    const { service, tokenService } = createService(db, user, 'ws_1');

    await service.createApiKey({ name: 'ci', expiresIn: '1y' }, user, 'ws_1');

    expect(tokenService.generateApiToken).toHaveBeenCalledWith(
      expect.objectContaining({ expiresIn: '1y' }),
    );
  });

  it('fails with a bad request when the insert returns no row', async () => {
    const db = createDb(undefined);
    const { service } = createService(db, user, 'ws_1');

    await expect(
      service.createApiKey({ name: 'ci' }, user, 'ws_1'),
    ).rejects.toThrow(BadRequestException);
  });
});

describe('ApiKeyService.listApiKeys', () => {
  it('lists non-deleted keys for the workspace, newest first', async () => {
    const db = createDb(null);
    const { service } = createService(db, null, null);

    const result = await service.listApiKeys('ws_1', {
      limit: 10,
      cursor: 'cursor_1',
    } as any);

    expect(executeWithCursorPagination).toHaveBeenCalledWith(
      db,
      expect.objectContaining({
        perPage: 10,
        cursor: 'cursor_1',
        fields: [{ expression: 'id', direction: 'desc' }],
      }),
    );
    expect(db.where).toHaveBeenCalledWith('workspaceId', '=', 'ws_1');
    expect(db.where).toHaveBeenCalledWith('deletedAt', 'is', null);
    expect(result.items).toEqual([{ id: 'key_1', name: 'ci' }]);
    expect(result.meta.nextCursor).toBe('cursor_2');
  });
});

describe('ApiKeyService.revokeApiKey', () => {
  it('soft-deletes within the workspace, ignoring already-revoked keys', async () => {
    const db = createDb(null);
    const { service } = createService(db, null, null);

    await service.revokeApiKey('key_1', 'ws_1');

    expect(db.updateTable).toHaveBeenCalledWith('apiKeys');
    expect(db.set).toHaveBeenCalledWith(
      expect.objectContaining({ deletedAt: expect.any(Date) }),
    );
    expect(db.where).toHaveBeenCalledWith('id', '=', 'key_1');
    expect(db.where).toHaveBeenCalledWith('workspaceId', '=', 'ws_1');
    expect(db.where).toHaveBeenCalledWith('deletedAt', 'is', null);
    expect(db.execute).toHaveBeenCalled();
  });
});
