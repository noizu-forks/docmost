import { NotFoundException } from '@nestjs/common';
import { createMockAbilityFactory } from '../test-helpers/casl.mock';
import { PageContentController } from './page-content.controller';

jest.mock('../../collaboration/collaboration.util', () => ({
  jsonToHtml: jest.fn().mockReturnValue('<p>html</p>'),
  jsonToMarkdown: jest.fn().mockReturnValue('# markdown'),
}));

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

  it('404s on an unknown page', async () => {
    const { controller } = createController({
      pageRepo: { findById: jest.fn().mockResolvedValue(null) },
    });

    await expect(
      controller.putContent('page_x', { content: '# hi' }, user),
    ).rejects.toThrow('Page not found');
  });

  it('converts content to the requested format on write', async () => {
    const { controller } = createController();

    const md = await controller.putContent(
      'page_1',
      { content: '# hello', format: 'markdown' },
      user,
    );
    const html = await controller.putContent(
      'page_1',
      { content: '# hello', format: 'html' },
      user,
    );
    const json = await controller.putContent(
      'page_1',
      { content: '# hello', format: 'json' },
      user,
    );

    expect(md.content).toBe('# markdown');
    expect(html.content).toBe('<p>html</p>');
    expect(json.content).toEqual({ type: 'doc', v: 2 });
  });

  it('keeps raw content when the updated page has none', async () => {
    const { controller } = createController({
      pageService: {
        update: jest.fn().mockResolvedValue({ ...page, content: null }),
      },
    });

    const result = await controller.putContent(
      'page_1',
      { content: '# hello', format: 'markdown' },
      user,
    );

    expect(result.content).toBeNull();
  });
});
