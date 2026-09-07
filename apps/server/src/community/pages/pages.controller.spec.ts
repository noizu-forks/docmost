import { NotFoundException } from '@nestjs/common';
import { createMockAbilityFactory } from '../test-helpers/casl.mock';
import { PagesController } from './pages.controller';

describe('PagesController (v1)', () => {
  const user = { id: 'user_1' } as any;
  const workspace = { id: 'ws_1' } as any;
  const page = {
    id: 'page_1',
    spaceId: 'space_1',
    parentPageId: null,
    position: 'a0',
    content: null,
  } as any;

  function createController(overrides: {
    pageRepo?: any;
    pageService?: any;
    pageAccessService?: any;
    abilities?: any;
  } = {}) {
    const pageRepo = {
      findById: jest.fn().mockResolvedValue(page),
      restorePage: jest.fn().mockResolvedValue(undefined),
      ...overrides.pageRepo,
    };
    const pageService = {
      getSidebarPages: jest.fn().mockResolvedValue({
        items: [{ id: 'page_1', title: 'Hello', updatedAt: new Date() }],
        meta: { hasNextPage: false },
      }),
      create: jest.fn().mockResolvedValue({ ...page, title: 'New' }),
      update: jest.fn().mockResolvedValue(page),
      movePage: jest.fn().mockResolvedValue(undefined),
      getPageBreadCrumbs: jest
        .fn()
        .mockResolvedValue([{ id: 'page_1', title: 'Hello' }]),
      removePage: jest.fn().mockResolvedValue(undefined),
      forceDelete: jest.fn().mockResolvedValue(undefined),
      ...overrides.pageService,
    };
    const pageAccessService = {
      validateCanEdit: jest.fn().mockResolvedValue({ hasRestriction: false }),
      validateCanView: jest.fn().mockResolvedValue(undefined),
      validateCanViewWithPermissions: jest
        .fn()
        .mockResolvedValue({ canEdit: true, hasRestriction: false }),
      ...overrides.pageAccessService,
    };
    const spaceAbility =
      overrides.abilities ??
      createMockAbilityFactory([
        { action: 'read', subject: 'page' },
        { action: 'edit', subject: 'page' },
        { action: 'create', subject: 'page' },
      ]);

    const controller = new PagesController(
      pageService,
      pageRepo,
      pageAccessService,
      spaceAbility,
    );

    return { controller, pageRepo, pageService, pageAccessService };
  }

  it('lists space pages in the {data, meta} envelope', async () => {
    const { controller, pageService } = createController();

    const result = await controller.listSpacePages(
      'space_1',
      undefined,
      { limit: 20 },
      user,
    );

    expect(result.data).toHaveLength(1);
    expect(result.meta.nextCursor).toBeNull();
    expect(pageService.getSidebarPages).toHaveBeenCalledWith(
      'space_1',
      { limit: 20, cursor: undefined },
      undefined,
      'user_1',
      true,
    );
  });

  it('creates a page under a parent', async () => {
    const { controller, pageService } = createController();

    await controller.createPage(
      'space_1',
      { title: 'New', parentId: 'parent_1', content: '# hi' },
      user,
      workspace,
    );

    expect(pageService.create).toHaveBeenCalledWith(
      'user_1',
      'ws_1',
      expect.objectContaining({ parentPageId: 'parent_1', spaceId: 'space_1' }),
    );
  });

  it('returns a page with permissions', async () => {
    const { controller } = createController();

    const result = await controller.getPage('page_1', {}, user);

    expect(result.permissions).toEqual({ canEdit: true, hasRestriction: false });
  });

  it('404s on an unknown page', async () => {
    const { controller } = createController({
      pageRepo: { findById: jest.fn().mockResolvedValue(null) },
    });

    await expect(controller.getPage('page_x', {}, user)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('patches title and moves parent via movePage', async () => {
    const { controller, pageService } = createController();

    await controller.patchPage(
      'page_1',
      { title: 'Renamed', parentId: 'parent_1' },
      user,
    );

    expect(pageService.update).toHaveBeenCalledWith(
      page,
      { pageId: 'page_1', title: 'Renamed' },
      user,
    );
    expect(pageService.movePage).toHaveBeenCalledWith(
      expect.objectContaining({ pageId: 'page_1', parentPageId: 'parent_1' }),
      page,
    );
  });

  it('trashes a page by default and is idempotent when already gone', async () => {
    const { controller, pageService } = createController();

    await controller.deletePage('page_1', {} as any, user, workspace);
    expect(pageService.removePage).toHaveBeenCalledWith(
      'page_1',
      'user_1',
      'ws_1',
    );

    const missing = createController({
      pageRepo: { findById: jest.fn().mockResolvedValue(null) },
    });
    await expect(
      missing.controller.deletePage('page_x', {} as any, user, workspace),
    ).resolves.toBeUndefined();
  });

  it('returns breadcrumbs in a {data} envelope', async () => {
    const { controller } = createController();

    const result = await controller.getBreadcrumbs('page_1', user);

    expect(result.data).toEqual([{ id: 'page_1', title: 'Hello' }]);
  });
});
