import { ForbiddenException } from '@nestjs/common';
import { createMockAbilityFactory } from '../test-helpers/casl.mock';
import { SearchController } from './search.controller';

describe('SearchController (v1)', () => {
  const user = { id: 'user_1' } as any;
  const workspace = { id: 'ws_1' } as any;

  function createController(overrides: { abilities?: any; searchService?: any } = {}) {
    const searchService = overrides.searchService ?? {
      searchPage: jest.fn().mockResolvedValue({
        items: [
          {
            id: 'page_1',
            title: 'Hello',
            highlight: 'hello world',
            space: { id: 'space_1' },
          },
        ],
      }),
    } as any;

    const controller = new SearchController(
      searchService,
      overrides.abilities ??
        createMockAbilityFactory([{ action: 'read', subject: 'page' }]),
    );

    return { controller, searchService };
  }

  it('maps q onto the core search and returns {data, meta}', async () => {
    const { controller, searchService } = createController();

    const result = await controller.search(
      { q: 'hello', limit: 10 },
      user,
      workspace,
    );

    expect(searchService.searchPage).toHaveBeenCalledWith(
      { query: 'hello', spaceId: undefined, limit: 10 },
      { userId: 'user_1', workspaceId: 'ws_1' },
    );
    expect(result.data).toEqual([
      {
        pageId: 'page_1',
        title: 'Hello',
        spaceId: 'space_1',
        snippet: 'hello world',
      },
    ]);
    expect(result.meta).toEqual({ nextCursor: null });
  });

  it('forbids searching a space without read access', async () => {
    const { controller, searchService } = createController({
      abilities: createMockAbilityFactory([]),
    });

    await expect(
      controller.search({ q: 'hello', spaceId: 'space_1' }, user, workspace),
    ).rejects.toThrow(ForbiddenException);
    expect(searchService.searchPage).not.toHaveBeenCalled();
  });

  it('falls back to the flat spaceId when the result has no space row', async () => {
    const { controller } = createController({
      searchService: {
        searchPage: jest.fn().mockResolvedValue({
          items: [
            {
              id: 'page_2',
              title: 'Flat',
              highlight: null,
              spaceId: 'space_9',
            },
          ],
        }),
      } as any,
    });

    const result = await controller.search(
      { q: 'flat', spaceId: 'space_1', limit: 5 },
      user,
      workspace,
    );

    expect(result.data).toEqual([
      { pageId: 'page_2', title: 'Flat', spaceId: 'space_9', snippet: null },
    ]);
  });
});
