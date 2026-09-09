import { NotFoundException, ForbiddenException, BadRequestException } from '@nestjs/common';
import { createMockAbilityFactory } from '../test-helpers/casl.mock';
import { PagesController } from './pages.controller';

jest.mock('../../collaboration/collaboration.util', () => ({
  jsonToHtml: jest.fn().mockReturnValue('<p>html</p>'),
  jsonToMarkdown: jest.fn().mockReturnValue('# markdown'),
}));

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

  it('forbids listing pages without space read access', async () => {
    const { controller } = createController({
      abilities: createMockAbilityFactory([]),
    });

    await expect(
      controller.listSpacePages('space_1', undefined, { limit: 20 }, user),
    ).rejects.toThrow(ForbiddenException);
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

  it('creates a root page via space create ability', async () => {
    const { controller, pageService, pageAccessService } = createController();

    await controller.createPage(
      'space_1',
      { title: 'Root' },
      user,
      workspace,
    );

    expect(pageAccessService.validateCanEdit).not.toHaveBeenCalled();
    expect(pageService.create).toHaveBeenCalledWith(
      'user_1',
      'ws_1',
      expect.objectContaining({ parentPageId: undefined, format: 'markdown' }),
    );
  });

  it('create response includes content, markdown-formatted (principle 5)', async () => {
    const withContent = { ...page, content: { type: 'doc' } };
    const { controller, pageRepo } = createController({
      pageRepo: {
        findById: jest.fn().mockResolvedValue(withContent),
      },
    });

    const result = await controller.createPage(
      'space_1',
      { title: 'New', content: '# hi' },
      user,
      workspace,
    );

    // create() returns baseFields only — the controller must re-fetch with
    // content so the client can encode the body straight off the response.
    expect(pageRepo.findById).toHaveBeenCalledWith('page_1', {
      includeSpace: true,
      includeContent: true,
    });
    expect(result.content).toBe('# markdown');
  });

  it('PATCH response returns markdown-formatted content, not the JSON tree', async () => {
    const { controller } = createController({
      pageRepo: {
        findById: jest.fn().mockResolvedValue({ ...page, content: { type: 'doc' } }),
      },
    });

    const result = await controller.patchPage('page_1', { title: 'T' }, user);

    expect(result.content).toBe('# markdown');
  });

  it('restore response returns markdown-formatted content', async () => {
    const { controller } = createController({
      pageRepo: {
        findById: jest.fn().mockResolvedValue({ ...page, content: { type: 'doc' } }),
      },
    });

    const result = await controller.restorePage('page_1', user, workspace);

    expect(result.content).toBe('# markdown');
  });

  it('404s when the parent page is unknown, deleted or in another space', async () => {
    for (const parent of [
      null,
      { ...page, id: 'parent_1', deletedAt: new Date() },
      { ...page, id: 'parent_1', spaceId: 'space_other' },
    ]) {
      const { controller } = createController({
        pageRepo: { findById: jest.fn().mockResolvedValue(parent) },
      });

      await expect(
        controller.createPage(
          'space_1',
          { title: 'New', parentId: 'parent_1' },
          user,
          workspace,
        ),
      ).rejects.toThrow('Parent page not found');
    }
  });

  it('forbids root-page creation without the create ability', async () => {
    const { controller } = createController({
      abilities: createMockAbilityFactory([]),
    });

    await expect(
      controller.createPage('space_1', { title: 'Nope' }, user, workspace),
    ).rejects.toThrow(ForbiddenException);
  });

  it('returns a page with permissions', async () => {
    const { controller } = createController();

    const result = await controller.getPage('page_1', {}, user);

    expect(result.permissions).toEqual({ canEdit: true, hasRestriction: false });
  });

  it('converts content to html or markdown on request', async () => {
    const contented = { ...page, content: { type: 'doc' } };
    const { controller } = createController({
      pageRepo: { findById: jest.fn().mockResolvedValue(contented) },
    });

    const html = await controller.getPage('page_1', { format: 'html' }, user);
    const md = await controller.getPage('page_1', { format: 'markdown' }, user);
    const json = await controller.getPage('page_1', { format: 'json' }, user);

    expect(html.content).toBe('<p>html</p>');
    expect(md.content).toBe('# markdown');
    expect(json.content).toEqual({ type: 'doc' });
  });

  it('includes children and breadcrumbs when asked', async () => {
    const { controller, pageService } = createController();

    const result = await controller.getPage(
      'page_1',
      { include: 'children, breadcrumbs' },
      user,
    );

    expect(result.children).toHaveLength(1);
    expect(result.breadcrumbs).toEqual([{ id: 'page_1', title: 'Hello' }]);
    expect(pageService.getSidebarPages).toHaveBeenCalledWith(
      'space_1',
      { limit: 100, cursor: undefined },
      'page_1',
      'user_1',
      true,
    );
  });

  it('404s on an unknown page', async () => {
    const { controller } = createController({
      pageRepo: { findById: jest.fn().mockResolvedValue(null) },
    });

    await expect(controller.getPage('page_x', {}, user)).rejects.toThrow(
      NotFoundException,
    );
  });

  it('lists children of a page', async () => {
    const { controller, pageService } = createController();

    const result = await controller.getChildren('page_1', { limit: 5 }, user);

    expect(result.data).toHaveLength(1);
    expect(pageService.getSidebarPages).toHaveBeenCalledWith(
      'space_1',
      { limit: 5, cursor: undefined },
      'page_1',
      'user_1',
      true,
    );
  });

  it('404s or forbids on the children route', async () => {
    const missing = createController({
      pageRepo: { findById: jest.fn().mockResolvedValue(null) },
    });
    await expect(
      missing.controller.getChildren('page_x', {}, user),
    ).rejects.toThrow(NotFoundException);

    const forbidden = createController({
      abilities: createMockAbilityFactory([]),
    });
    await expect(
      forbidden.controller.getChildren('page_1', {}, user),
    ).rejects.toThrow(ForbiddenException);
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

  it('patches the title without moving when parentId is unchanged', async () => {
    const { controller, pageService, pageRepo } = createController();
    pageRepo.findById.mockResolvedValue({ ...page, parentPageId: 'parent_1' });

    await controller.patchPage(
      'page_1',
      { title: 'Renamed', parentId: 'parent_1' },
      user,
    );

    expect(pageService.update).toHaveBeenCalled();
    expect(pageService.movePage).not.toHaveBeenCalled();
  });

  it('validates the move target parent', async () => {
    // unknown parent -> 404
    const missing = createController({
      pageRepo: {
        findById: jest
          .fn()
          .mockResolvedValueOnce(page)
          .mockResolvedValueOnce(null),
      },
    });
    await expect(
      missing.controller.patchPage('page_1', { parentId: 'parent_x' }, user),
    ).rejects.toThrow('Target parent page not found');

    // deleted parent -> 404
    const deleted = createController({
      pageRepo: {
        findById: jest
          .fn()
          .mockResolvedValueOnce(page)
          .mockResolvedValueOnce({ ...page, id: 'parent_1', deletedAt: new Date() }),
      },
    });
    await expect(
      deleted.controller.patchPage('page_1', { parentId: 'parent_1' }, user),
    ).rejects.toThrow('Target parent page not found');

    // parent in another space -> 400
    const crossSpace = createController({
      pageRepo: {
        findById: jest
          .fn()
          .mockResolvedValueOnce(page)
          .mockResolvedValueOnce({ ...page, id: 'parent_1', spaceId: 'space_other' }),
      },
    });
    await expect(
      crossSpace.controller.patchPage('page_1', { parentId: 'parent_1' }, user),
    ).rejects.toThrow(BadRequestException);
  });

  it('allows detaching a page to the workspace root', async () => {
    const detached = { ...page, parentPageId: 'parent_1' };
    const { controller, pageService } = createController({
      pageRepo: { findById: jest.fn().mockResolvedValue(detached) },
    });

    await controller.patchPage('page_1', { parentId: null }, user);

    expect(pageService.movePage).toHaveBeenCalledWith(
      expect.objectContaining({ parentPageId: null }),
      detached,
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

  it('force-deletes for space admins and forbids members', async () => {
    const admin = createController({
      abilities: createMockAbilityFactory([{ action: 'manage', subject: 'settings' }]),
    });
    await admin.controller.deletePage(
      'page_1',
      { permanent: 'true' } as any,
      user,
      workspace,
    );
    expect(admin.pageService.forceDelete).toHaveBeenCalledWith('page_1', 'ws_1');

    const member = createController({
      abilities: createMockAbilityFactory([]),
    });
    await expect(
      member.controller.deletePage(
        'page_1',
        { permanent: 'true' } as any,
        user,
        workspace,
      ),
    ).rejects.toThrow('Only space admins can permanently delete pages');
    expect(member.pageService.forceDelete).not.toHaveBeenCalled();
  });

  it('restores a trashed page', async () => {
    const { controller, pageRepo } = createController();

    const result = await controller.restorePage('page_1', user, workspace);

    expect(pageRepo.restorePage).toHaveBeenCalledWith('page_1', 'ws_1');
    expect(result.id).toBe('page_1');
  });

  it('404s or forbids on restore', async () => {
    const missing = createController({
      pageRepo: { findById: jest.fn().mockResolvedValue(null) },
    });
    await expect(
      missing.controller.restorePage('page_x', user, workspace),
    ).rejects.toThrow(NotFoundException);

    const forbidden = createController({
      abilities: createMockAbilityFactory([]),
    });
    await expect(
      forbidden.controller.restorePage('page_1', user, workspace),
    ).rejects.toThrow(ForbiddenException);
  });

  it('returns breadcrumbs in a {data} envelope', async () => {
    const { controller } = createController();

    const result = await controller.getBreadcrumbs('page_1', user);

    expect(result.data).toEqual([{ id: 'page_1', title: 'Hello' }]);
  });
});
