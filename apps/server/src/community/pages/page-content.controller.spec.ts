import { createMockAbilityFactory } from '../test-helpers/casl.mock';
import { PageContentController } from './page-content.controller';

describe('PageContentController (v1)', () => {
  const user = { id: 'user_1' } as any;
  const page = { id: 'page_1', spaceId: 'space_1', content: { type: 'doc' } } as any;

  function createController(overrides: { pageRepo?: any; pageService?: any } = {}) {
    const pageRepo = {
      findById: jest.fn().mockResolvedValue(page),
      ...overrides.pageRepo,
    };
    const pageService = {
      update: jest.fn().mockResolvedValue({ ...page, content: { type: 'doc', v: 2 } }),
      ...overrides.pageService,
    };
    const pageAccessService = {
      validateCanEdit: jest.fn().mockResolvedValue({ hasRestriction: false }),
    } as any;

    const controller = new PageContentController(
      pageService,
      pageRepo,
      pageAccessService,
    );

    return { controller, pageService, pageAccessService };
  }

  it('replaces content by default and returns permissions', async () => {
    const { controller, pageService } = createController();

    const result = await controller.putContent(
      'page_1',
      { content: '# hello' },
      user,
    );

    expect(pageService.update).toHaveBeenCalledWith(
      page,
      {
        pageId: 'page_1',
        content: '# hello',
        operation: 'replace',
        format: 'markdown',
      },
      user,
    );
    expect(result.permissions).toEqual({ canEdit: true, hasRestriction: false });
  });

  it('honors append/prepend operations', async () => {
    const { controller, pageService } = createController();

    await controller.putContent(
      'page_1',
      { content: 'more', operation: 'append', format: 'markdown' },
      user,
    );

    expect(pageService.update).toHaveBeenCalledWith(
      page,
      { pageId: 'page_1', content: 'more', operation: 'append', format: 'markdown' },
      user,
    );
  });
});
