import { BadRequestException, NotFoundException } from '@nestjs/common';
import { createMockAbilityFactory } from '../test-helpers/casl.mock';
import { PageAccessController } from './page-access.controller';

describe('PageAccessController (v1)', () => {
  const user = { id: 'user_1' } as any;
  const workspace = { id: 'ws_1' } as any;
  const page = { id: 'page_1', spaceId: 'space_1', workspaceId: 'ws_1' } as any;

  function createController(overrides: Record<string, any> = {}) {
    const pageRepo = {
      findById: jest.fn().mockResolvedValue(page),
      ...overrides.pageRepo,
    };
    const pagePermissionRepo = {
      findPageAccessByPageId: jest
        .fn()
        .mockResolvedValue({ id: 'access_1', pageId: 'page_1' }),
      findRestrictedAncestor: jest.fn().mockResolvedValue(undefined),
      insertPageAccess: jest
        .fn()
        .mockResolvedValue({ id: 'access_1', pageId: 'page_1' }),
      deletePageAccess: jest.fn().mockResolvedValue(undefined),
      insertPagePermissions: jest.fn().mockResolvedValue(undefined),
      ...overrides.pagePermissionRepo,
    };
    const pageAccessService = {
      validateCanEdit: jest.fn().mockResolvedValue({ hasRestriction: false }),
      validateCanViewWithPermissions: jest
        .fn()
        .mockResolvedValue({ canEdit: true, hasRestriction: true }),
      ...overrides.pageAccessService,
    };
    const grantsMapper = {
      listGrants: jest.fn().mockResolvedValue({
        items: [
          { id: 'grant_1', type: 'user', principalId: 'user_2', role: 'writer' },
        ],
        meta: { hasNextPage: false },
      }),
      findGrantById: jest
        .fn()
        .mockResolvedValue({ id: 'grant_1', type: 'user', principalId: 'user_2', role: 'writer' }),
      updateRoleById: jest.fn().mockResolvedValue(undefined),
      deleteById: jest.fn().mockResolvedValue(undefined),
      ...overrides.grantsMapper,
    };
    const spaceAbility =
      overrides.abilities ??
      createMockAbilityFactory([
        { action: 'read', subject: 'page' },
        { action: 'edit', subject: 'page' },
      ]);

    const controller = new PageAccessController(
      pageRepo,
      pagePermissionRepo,
      pageAccessService,
      grantsMapper,
    );

    return { controller, pagePermissionRepo, pageAccessService, grantsMapper };
  }

  it('reports restriction, access and embedded grants', async () => {
    const { controller } = createController();

    const result = await controller.getAccess('page_1', {}, user);

    expect(result.restriction).toBe('direct');
    expect(result.canAccess).toBe(true);
    expect(result.canEdit).toBe(true);
    expect(result.grants.data).toEqual([
      { id: 'grant_1', type: 'user', principalId: 'user_2', role: 'writer' },
    ]);
  });

  it('reports inherited restriction when only an ancestor is restricted', async () => {
    const { controller } = createController({
      pagePermissionRepo: {
        findPageAccessByPageId: jest.fn().mockResolvedValue(null),
        findRestrictedAncestor: jest
          .fn()
          .mockResolvedValue({ pageId: 'ancestor_1' }),
      },
    });

    const result = await controller.getAccess('page_1', {}, user);

    expect(result.restriction).toBe('inherited');
    expect(result.grants.data).toEqual([]);
  });

  it('reports restriction none and canAccess false for blocked callers', async () => {
    const { controller } = createController({
      pagePermissionRepo: {
        findPageAccessByPageId: jest.fn().mockResolvedValue(null),
        findRestrictedAncestor: jest.fn().mockResolvedValue(undefined),
      },
      pageAccessService: {
        validateCanViewWithPermissions: jest
          .fn()
          .mockRejectedValue(new Error('forbidden')),
      },
    });

    const result = await controller.getAccess('page_1', {}, user);

    expect(result.restriction).toBe('none');
    expect(result.canAccess).toBe(false);
    expect(result.canEdit).toBe(false);
  });

  it('PUT restriction {restricted:true} inserts page access idempotently', async () => {
    const { controller, pagePermissionRepo } = createController({
      pagePermissionRepo: {
        findPageAccessByPageId: jest
          .fn()
          .mockResolvedValueOnce(null) // first PUT: nothing yet
          .mockResolvedValue({ id: 'access_1', pageId: 'page_1' }),
      },
    });

    const result = await controller.putRestriction(
      'page_1',
      { restricted: true },
      user,
      workspace,
    );

    expect(result.restriction).toBe('direct');
    expect(pagePermissionRepo.insertPageAccess).toHaveBeenCalledWith(
      expect.objectContaining({ pageId: 'page_1', accessLevel: 'restricted' }),
    );

    await controller.putRestriction('page_1', { restricted: true }, user, workspace);
    expect(pagePermissionRepo.insertPageAccess).toHaveBeenCalledTimes(1);
  });

  it('PUT restriction {restricted:false} deletes page access', async () => {
    const { controller, pagePermissionRepo } = createController();

    const result = await controller.putRestriction(
      'page_1',
      { restricted: false },
      user,
      workspace,
    );

    expect(result.restriction).toBe('none');
    expect(pagePermissionRepo.deletePageAccess).toHaveBeenCalledWith('page_1');
  });

  it('POST grants inserts rows via the mapper and returns the grant list', async () => {
    const { controller, pagePermissionRepo, grantsMapper } = createController();
    grantsMapper.listGrants.mockResolvedValue({
      items: [{ id: 'grant_9', type: 'group', principalId: 'group_1', role: 'reader' }],
      meta: { hasNextPage: false },
    });

    const result = await controller.postGrants(
      'page_1',
      {
        grants: [
          { type: 'group', principalId: 'group_1', role: 'reader' },
          { type: 'user', principalId: 'user_2', role: 'writer' },
        ],
      } as any,
      user,
      workspace,
    );

    expect(pagePermissionRepo.insertPagePermissions).toHaveBeenCalledWith([
      {
        pageAccessId: 'access_1',
        userId: undefined,
        groupId: 'group_1',
        role: 'reader',
        addedById: 'user_1',
      },
      {
        pageAccessId: 'access_1',
        userId: 'user_2',
        groupId: undefined,
        role: 'writer',
        addedById: 'user_1',
      },
    ]);
    expect(result.data).toEqual([
      { id: 'grant_9', type: 'group', principalId: 'group_1', role: 'reader' },
    ]);
  });

  it('PATCH grant updates the role by stable grant id', async () => {
    const { controller, grantsMapper } = createController();

    const result = await controller.patchGrant(
      'page_1',
      'grant_1',
      { role: 'reader' } as any,
      user,
    );

    expect(grantsMapper.updateRoleById).toHaveBeenCalledWith(
      'grant_1',
      'access_1',
      'reader',
    );
    expect(result.role).toBe('writer');
  });

  it('DELETE grant is idempotent (204)', async () => {
    const { controller, grantsMapper } = createController();
    grantsMapper.deleteById.mockResolvedValue(undefined);

    await expect(
      controller.deleteGrant('page_1', 'grant_1', user),
    ).resolves.toBeUndefined();
    expect(grantsMapper.deleteById).toHaveBeenCalledWith('grant_1', 'access_1');
  });

  it('404s on unknown page', async () => {
    const { controller } = createController({
      pageRepo: { findById: jest.fn().mockResolvedValue(null) },
    });

    await expect(controller.getAccess('page_x', {}, user)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('400s on an empty pageId', async () => {
    const { controller } = createController();

    await expect(
      controller.getAccess(undefined as any, {}, user),
    ).rejects.toThrow(BadRequestException);
  });

  it('404s PATCH grant when the page is not restricted', async () => {
    const { controller, grantsMapper } = createController({
      pagePermissionRepo: {
        findPageAccessByPageId: jest.fn().mockResolvedValue(null),
      },
    });

    await expect(
      controller.patchGrant('page_1', 'grant_1', { role: 'reader' } as any, user),
    ).rejects.toThrow('Page is not restricted');
    expect(grantsMapper.updateRoleById).not.toHaveBeenCalled();
  });

  it('DELETE grant is a no-op 204 when the page is not restricted', async () => {
    const { controller, grantsMapper } = createController({
      pagePermissionRepo: {
        findPageAccessByPageId: jest.fn().mockResolvedValue(null),
      },
    });

    await expect(
      controller.deleteGrant('page_1', 'grant_1', user),
    ).resolves.toBeUndefined();
    expect(grantsMapper.deleteById).not.toHaveBeenCalled();
  });
});
