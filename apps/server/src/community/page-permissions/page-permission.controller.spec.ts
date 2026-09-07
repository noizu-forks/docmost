import { NotFoundException } from '@nestjs/common';
import { PagePermissionController } from './page-permission.controller';

function createController(overrides: {
  pagePermissionRepo?: any;
  pageRepo?: any;
  pageAccessService?: any;
} = {}) {
  const defaultPagePermissionRepo = {
    findPageAccessByPageId: jest.fn().mockResolvedValue(undefined),
    findRestrictedAncestor: jest.fn().mockResolvedValue(undefined),
    insertPageAccess: jest
      .fn()
      .mockResolvedValue({ id: 'access_1', pageId: 'page_1' }),
    deletePageAccess: jest.fn().mockResolvedValue(undefined),
    insertPagePermissions: jest.fn().mockResolvedValue(undefined),
    updatePagePermissionRole: jest.fn().mockResolvedValue(undefined),
    deletePagePermissionsByUserIds: jest.fn().mockResolvedValue(undefined),
    deletePagePermissionsByGroupIds: jest.fn().mockResolvedValue(undefined),
    getPagePermissionsPaginated: jest.fn().mockResolvedValue({
      items: [
        { type: 'user', id: 'user_1', role: 'reader' },
        { type: 'group', id: 'group_1', role: 'writer' },
      ],
      meta: { hasNextPage: true, nextCursor: 'cursor_1' },
    }),
  };
  const pagePermissionRepo = {
    ...defaultPagePermissionRepo,
    ...overrides.pagePermissionRepo,
  };
  const pageRepo = overrides.pageRepo ?? {
    findById: jest
      .fn()
      .mockResolvedValue({ id: 'page_1', spaceId: 'space_1' }),
  };
  const pageAccessService = overrides.pageAccessService ?? {
    validateCanEdit: jest.fn().mockResolvedValue({ hasRestriction: false }),
    validateCanViewWithPermissions: jest
      .fn()
      .mockResolvedValue({ canEdit: true, hasRestriction: false }),
  };

  const controller = new PagePermissionController(
    pageRepo,
    pagePermissionRepo,
    pageAccessService,
  );

  return { controller, pageRepo, pagePermissionRepo, pageAccessService };
}

const user = { id: 'user_1' } as any;
const workspace = { id: 'ws_1' } as any;

describe('PagePermissionController', () => {
  describe('permission-info', () => {
    it('reports a direct restriction', async () => {
      const { controller, pagePermissionRepo } = createController({
        pagePermissionRepo: {
          findPageAccessByPageId: jest
            .fn()
            .mockResolvedValue({ id: 'access_1' }),
        } as any,
      });

      const result = await controller.getPermissionInfo(
        { pageId: 'page_1' },
        user,
      );

      expect(result.hasDirectRestriction).toBe(true);
      expect(result.hasInheritedRestriction).toBe(false);
      expect(result.canAccess).toBe(true);
      expect(result.canEdit).toBe(true);
      expect(result.permissions).toEqual([]);
      expect(pagePermissionRepo.findRestrictedAncestor).not.toHaveBeenCalled();
    });

    it('reports an inherited restriction when only an ancestor is restricted', async () => {
      const { controller } = createController({
        pagePermissionRepo: {
          findPageAccessByPageId: jest.fn().mockResolvedValue(undefined),
          findRestrictedAncestor: jest
            .fn()
            .mockResolvedValue({ pageId: 'ancestor_1' }),
        } as any,
      });

      const result = await controller.getPermissionInfo(
        { pageId: 'page_1' },
        user,
      );

      expect(result.hasDirectRestriction).toBe(false);
      expect(result.hasInheritedRestriction).toBe(true);
    });

    it('reports canAccess=false when the caller cannot view the page', async () => {
      const { controller } = createController({
        pageAccessService: {
          validateCanViewWithPermissions: jest
            .fn()
            .mockRejectedValue(new Error('forbidden')),
        } as any,
      });

      const result = await controller.getPermissionInfo(
        { pageId: 'page_1' },
        user,
      );

      expect(result.canAccess).toBe(false);
      expect(result.canEdit).toBe(false);
    });
  });

  describe('permissions', () => {
    it('returns mapped permissions and meta.nextCursor', async () => {
      const { controller, pagePermissionRepo } = createController({
        pagePermissionRepo: {
          findPageAccessByPageId: jest
            .fn()
            .mockResolvedValue({ id: 'access_1' }),
          getPagePermissionsPaginated: jest.fn().mockResolvedValue({
            items: [
              { type: 'user', id: 'user_1', role: 'reader' },
              { type: 'group', id: 'group_1', role: 'writer' },
            ],
            meta: { hasNextPage: true, nextCursor: 'cursor_1' },
          }),
        } as any,
      });

      const result = await controller.getPermissions(
        { pageId: 'page_1', limit: 20 } as any,
        user,
      );

      expect(result.permissions).toEqual([
        { type: 'user', id: 'user_1', role: 'reader' },
        { type: 'group', id: 'group_1', role: 'writer' },
      ]);
      expect(result.meta).toEqual({ nextCursor: 'cursor_1' });
      expect(pagePermissionRepo.getPagePermissionsPaginated).toHaveBeenCalledWith(
        'access_1',
        { pageId: 'page_1', limit: 20 } as any,
      );
    });

    it('returns an empty list when the page is not restricted', async () => {
      const { controller } = createController();

      const result = await controller.getPermissions(
        { pageId: 'page_1', limit: 20 } as any,
        user,
      );

      expect(result.permissions).toEqual([]);
      expect(result.meta.nextCursor).toBeNull();
    });
  });

  describe('restrict', () => {
    it('inserts a restricted page access', async () => {
      const { controller, pagePermissionRepo } = createController();

      await controller.restrictPage({ pageId: 'page_1' }, user, workspace);

      expect(pagePermissionRepo.insertPageAccess).toHaveBeenCalledWith(
        expect.objectContaining({
          pageId: 'page_1',
          accessLevel: 'restricted',
          creatorId: 'user_1',
        }),
      );
    });

    it('is idempotent when the page is already restricted', async () => {
      const { controller, pagePermissionRepo } = createController({
        pagePermissionRepo: {
          findPageAccessByPageId: jest
            .fn()
            .mockResolvedValue({ id: 'access_1' }),
        } as any,
      });

      await controller.restrictPage({ pageId: 'page_1' }, user, workspace);

      expect(pagePermissionRepo.insertPageAccess).not.toHaveBeenCalled();
    });
  });

  describe('remove-restriction', () => {
    it('deletes the page access', async () => {
      const { controller, pagePermissionRepo } = createController({
        pagePermissionRepo: {
          findPageAccessByPageId: jest
            .fn()
            .mockResolvedValue({ id: 'access_1' }),
          deletePageAccess: jest.fn().mockResolvedValue(undefined),
        } as any,
      });

      await controller.removeRestriction({ pageId: 'page_1' }, user);

      expect(pagePermissionRepo.deletePageAccess).toHaveBeenCalledWith('page_1');
    });

    it('404s when the page is not restricted', async () => {
      const { controller } = createController();

      await expect(
        controller.removeRestriction({ pageId: 'page_1' }, user),
      ).rejects.toThrow(NotFoundException);
    });
  });

  describe('add-permission', () => {
    it('inserts user permissions', async () => {
      const { controller, pagePermissionRepo } = createController();

      await controller.addPermission(
        { pageId: 'page_1', role: 'writer', userIds: ['user_2'] } as any,
        user,
        workspace,
      );

      expect(pagePermissionRepo.insertPagePermissions).toHaveBeenCalledWith([
        {
          pageAccessId: 'access_1',
          userId: 'user_2',
          role: 'writer',
          addedById: 'user_1',
        },
      ]);
    });

    it('rejects when neither userIds nor groupIds is provided', async () => {
      const { controller } = createController();

      await expect(
        controller.addPermission(
          { pageId: 'page_1', role: 'writer' } as any,
          user,
          workspace,
        ),
      ).rejects.toThrow();
    });
  });

  describe('update-permission', () => {
    it('updates the role for a user', async () => {
      const { controller, pagePermissionRepo } = createController({
        pagePermissionRepo: {
          findPageAccessByPageId: jest
            .fn()
            .mockResolvedValue({ id: 'access_1' }),
          updatePagePermissionRole: jest.fn().mockResolvedValue(undefined),
        } as any,
      });

      await controller.updatePermission(
        { pageId: 'page_1', userId: 'user_2', role: 'reader' } as any,
        user,
      );

      expect(pagePermissionRepo.updatePagePermissionRole).toHaveBeenCalledWith(
        'access_1',
        'reader',
        { userId: 'user_2', groupId: undefined },
      );
    });
  });

  describe('remove-permission', () => {
    it('deletes by userIds and groupIds', async () => {
      const { controller, pagePermissionRepo } = createController({
        pagePermissionRepo: {
          findPageAccessByPageId: jest
            .fn()
            .mockResolvedValue({ id: 'access_1' }),
          deletePagePermissionsByUserIds: jest.fn().mockResolvedValue(undefined),
          deletePagePermissionsByGroupIds: jest
            .fn()
            .mockResolvedValue(undefined),
        } as any,
      });

      await controller.removePermission(
        { pageId: 'page_1', userIds: ['user_2'], groupIds: ['group_2'] },
        user,
      );

      expect(
        pagePermissionRepo.deletePagePermissionsByUserIds,
      ).toHaveBeenCalledWith('access_1', ['user_2']);
      expect(
        pagePermissionRepo.deletePagePermissionsByGroupIds,
      ).toHaveBeenCalledWith('access_1', ['group_2']);
    });
  });
});
