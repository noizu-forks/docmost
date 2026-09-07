import { ForbiddenException } from '@nestjs/common';
import { createMockAbilityFactory } from '../test-helpers/casl.mock';
import { ApiKeyController } from './api-key.controller';

// CASL mock helper lives next to the community specs.
describe('ApiKeyController (v1)', () => {
  const user = { id: 'user_1', role: 'admin' } as any;
  const workspace = { id: 'ws_1' } as any;

  function createController(abilityFactory?: any) {
    const apiKeyService = {
      createApiKey: jest
        .fn()
        .mockResolvedValue({ id: 'key_1', name: 'ci', token: 'tok' }),
      listApiKeys: jest.fn().mockResolvedValue({
        items: [{ id: 'key_1', name: 'ci' }],
        meta: { hasNextPage: false },
      }),
      revokeApiKey: jest.fn().mockResolvedValue(undefined),
    } as any;

    const controller = new ApiKeyController(
      apiKeyService,
      abilityFactory ??
        createMockAbilityFactory([{ action: 'manage', subject: 'api_key' }]),
    );

    return { controller, apiKeyService };
  }

  it('mints a key for admins', async () => {
    const { controller, apiKeyService } = createController();

    const result = await controller.createApiKey(
      { name: 'ci' },
      user,
      workspace,
    );

    expect(result).toEqual({ id: 'key_1', name: 'ci', token: 'tok' });
    expect(apiKeyService.createApiKey).toHaveBeenCalledWith(
      { name: 'ci' },
      user,
      'ws_1',
    );
  });

  it('forbids members from managing keys', async () => {
    const { controller } = createController(
      createMockAbilityFactory([{ action: 'create', subject: 'api_key' }]),
    );

    await expect(
      controller.createApiKey({ name: 'ci' }, user, workspace),
    ).rejects.toThrow(ForbiddenException);
  });

  it('lists keys without tokens', async () => {
    const { controller, apiKeyService } = createController();

    const result = await controller.listApiKeys({ limit: 10 }, user, workspace);

    expect(result.data).toEqual([{ id: 'key_1', name: 'ci' }]);
    expect(apiKeyService.listApiKeys).toHaveBeenCalledWith('ws_1', {
      limit: 10,
      cursor: undefined,
    });
  });

  it('revokes idempotently (204)', async () => {
    const { controller, apiKeyService } = createController();

    await expect(
      controller.revokeApiKey('key_1', user, workspace),
    ).resolves.toBeUndefined();
    await expect(
      controller.revokeApiKey('missing', user, workspace),
    ).resolves.toBeUndefined();
    expect(apiKeyService.revokeApiKey).toHaveBeenCalledTimes(2);
  });
});
