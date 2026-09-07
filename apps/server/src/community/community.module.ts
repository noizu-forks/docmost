import { Module } from '@nestjs/common';
import { TokenModule } from '../core/auth/token.module';
import { PageAccessModule } from '../core/page/page-access/page-access.module';
import { ApiKeyController } from './api-key/api-key.controller';
import { ApiKeyService } from './api-key/api-key.service';
import { PagePermissionController } from './page-permissions/page-permission.controller';

/**
 * Community (AGPL) API layer: API-key management plus a REST surface over
 * the existing page-permission data layer. No ee/ imports; when the real
 * enterprise API-key module is present it takes precedence in the JWT
 * strategy (see core/auth/strategies/jwt.strategy.ts).
 */
@Module({
  imports: [TokenModule, PageAccessModule],
  controllers: [ApiKeyController, PagePermissionController],
  providers: [ApiKeyService],
  exports: [ApiKeyService],
})
export class CommunityModule {}
