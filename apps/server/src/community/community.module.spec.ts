import { CommunityModule } from './community.module';
import { ApiKeyController } from './api-key/api-key.controller';
import { ApiKeyService } from './api-key/api-key.service';
import { GrantsMapper } from './access/grants.mapper';

// the imported core feature modules bootstrap environment validation at the
// module level; the unit test only inspects the community wiring
jest.mock('../core/auth/token.module', () => ({ TokenModule: class {} }));
jest.mock('../core/page/page.module', () => ({ PageModule: class {} }));
jest.mock('../core/page/page-access/page-access.module', () => ({
  PageAccessModule: class {},
}));
jest.mock('../core/share/share.module', () => ({ ShareModule: class {} }));
jest.mock('../core/space/space.module', () => ({ SpaceModule: class {} }));
jest.mock('../core/search/search.module', () => ({ SearchModule: class {} }));

describe('CommunityModule', () => {
  it('wires the v1 controllers, providers and exports', () => {
    expect(CommunityModule).toBeDefined();
    const controllers = Reflect.getMetadata('controllers', CommunityModule);
    const providers = Reflect.getMetadata('providers', CommunityModule);
    const exportsMeta = Reflect.getMetadata('exports', CommunityModule);
    expect(controllers).toContain(ApiKeyController);
    expect(controllers).toHaveLength(7);
    expect(providers).toEqual(
      expect.arrayContaining([ApiKeyService, GrantsMapper]),
    );
    expect(exportsMeta).toEqual([ApiKeyService]);
  });
});
