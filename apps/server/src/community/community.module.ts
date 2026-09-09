import { Module } from '@nestjs/common';
import { TokenModule } from '../core/auth/token.module';
import { PageModule } from '../core/page/page.module';
import { PageAccessModule } from '../core/page/page-access/page-access.module';
import { ShareModule } from '../core/share/share.module';
import { SpaceModule } from '../core/space/space.module';
import { SearchModule } from '../core/search/search.module';
import { ApiKeyController } from './api-key/api-key.controller';
import { ApiKeyService } from './api-key/api-key.service';
import { GrantsMapper } from './access/grants.mapper';
import { PageAccessController } from './access/page-access.controller';
import { PageContentController } from './pages/page-content.controller';
import { PagesController } from './pages/pages.controller';
import { SharesController } from './shares/shares.controller';
import { SpacesController } from './spaces/spaces.controller';
import { SearchController } from './search/search.controller';

/**
 * Community (AGPL) v1 API layer: resource-oriented REST under /api/v1
 * (api keys, spaces, pages, shares, page access, search). No ee/ imports;
 * when the real enterprise API-key module is present it takes precedence in
 * the JWT strategy (see core/auth/strategies/jwt.strategy.ts).
 */
@Module({
  imports: [
    TokenModule,
    PageModule,
    PageAccessModule,
    ShareModule,
    SpaceModule,
    SearchModule,
  ],
  controllers: [
    ApiKeyController,
    SpacesController,
    PagesController,
    PageContentController,
    SharesController,
    PageAccessController,
    SearchController,
  ],
  providers: [ApiKeyService, GrantsMapper],
  exports: [ApiKeyService],
})
export class CommunityModule {}
