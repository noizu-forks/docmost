import { ForbiddenException } from '@nestjs/common';
import { createMockAbilityFactory } from '../test-helpers/casl.mock';
import { SharesController } from './shares.controller';

describe('SharesController (v1)', () => {
  const user = { id: 'user_1' } as any;
  const workspace = { id: 'ws_1' } as any;
  const page = {
    id: 'page_1',
    spaceId: 'space_1',
    workspaceId: 'ws_1',
  } as any;

  function createController(overrides: Record<string, any> = {}) {
    const shareService = {
      getShareForPage: jest.fn().mockResolvedValue(undefined),
      createShare: jest
        .fn()
        .mockResolvedValue({ id: 'share_1', key: 'sharekey1' }),
      updateShare: jest
        .fn()
        .mockResolvedValue({ id: 'share_1', key: 'sharekey1' }),
      isSharingAllowed: jest.fn().mockResolvedValue(true),
      ...overrides.shareService,
    };
    const shareRepo = {
      deleteShare: jest.fn().mockResolvedValue(undefined),
    } as any;
    const pageRepo = {
      findById: jest.fn().mockResolvedValue(page),
      ...overrides.pageRepo,
    };
    const pagePermissionRepo = {
      hasRestrictedAncestor: jest.fn().mockResolvedValue(false),
      ...overrides.pagePermissionRepo,
    };
    const pageAccessService = {
      validateCanEdit: jest.fn().mockResolvedValue({ hasRestriction: false }),
      ...overrides.pageAccessService,
    };
    const environmentService = {
      getAppUrl: jest.fn().mockReturnValue('https://docmost.example'),
    } as any;

    const controller = new SharesController(
      shareService,
      shareRepo,
      pageRepo,
      pagePermissionRepo,
      pageAccessService,
      environmentService,
    );

    return {
      controller,
      shareService,
      shareRepo,
      pagePermissionRepo,
    };
  }

  it('returns shared:false when no share exists', async () => {
    const { controller } = createController();

    const result = await controller.getShare('page_1', workspace);

    expect(result).toEqual({ shared: false });
  });

  it('returns the share with a server-computed publicUrl', async () => {
    const { controller } = createController({
      shareService: {
        getShareForPage: jest.fn().mockResolvedValue({
          id: 'share_1',
          key: 'sharekey1',
          includeSubPages: true,
          searchIndexing: false,
          level: 0,
        }),
      },
    });

    const result = await controller.getShare('page_1', workspace);

    expect(result).toMatchObject({
      shared: true,
      key: 'sharekey1',
      level: 0,
      publicUrl: 'https://docmost.example/share/sharekey1',
    });
  });

  it('creates a share on PUT {shared:true}', async () => {
    const { controller, shareService } = createController();

    const result = await controller.putShare(
      'page_1',
      { shared: true, includeSubPages: true },
      user,
      workspace,
    );

    expect(shareService.createShare).toHaveBeenCalled();
    expect(result.shared).toBe(true);
    expect(result.publicUrl).toContain('/share/sharekey1');
  });

  it('updates an existing direct share on PUT', async () => {
    const { controller, shareService } = createController({
      shareService: {
        getShareForPage: jest
          .fn()
          .mockResolvedValueOnce({ id: 'share_1', key: 'sharekey1', level: 0 })
          .mockResolvedValueOnce({ id: 'share_1', key: 'sharekey1', level: 0 }),
        updateShare: jest
          .fn()
          .mockResolvedValue({ id: 'share_1', key: 'sharekey1' }),
        isSharingAllowed: jest.fn().mockResolvedValue(true),
      },
    });

    const result = await controller.putShare(
      'page_1',
      { shared: true, searchIndexing: true },
      user,
      workspace,
    );

    expect(shareService.updateShare).toHaveBeenCalled();
    expect(result.shared).toBe(true);
  });

  it('deletes on PUT {shared:false}', async () => {
    const { controller, shareRepo } = createController({
      shareService: {
        getShareForPage: jest
          .fn()
          .mockResolvedValue({ id: 'share_1', key: 'sharekey1', level: 0 }),
      },
    });

    const result = await controller.putShare(
      'page_1',
      { shared: false },
      user,
      workspace,
    );

    expect(shareRepo.deleteShare).toHaveBeenCalledWith('share_1');
    expect(result).toEqual({ shared: false });
  });

  it('blocks sharing restricted pages', async () => {
    const { controller } = createController({
      pagePermissionRepo: {
        hasRestrictedAncestor: jest.fn().mockResolvedValue(true),
      },
    });

    await expect(
      controller.putShare('page_1', { shared: true }, user, workspace),
    ).rejects.toThrow(ForbiddenException);
  });
});
