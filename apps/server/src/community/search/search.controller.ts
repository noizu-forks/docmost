import {
  Controller,
  ForbiddenException,
  Get,
  Query,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { AuthUser } from '../../common/decorators/auth-user.decorator';
import { AuthWorkspace } from '../../common/decorators/auth-workspace.decorator';
import { User, Workspace } from '@docmost/db/types/entity.types';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { SearchService } from '../../core/search/search.service';
import SpaceAbilityFactory from '../../core/casl/abilities/space-ability.factory';
import {
  SpaceCaslAction,
  SpaceCaslSubject,
} from '../../core/casl/interfaces/space-ability.type';
import { V1ExceptionFilter } from '../http/error-filter';
import { V1SearchDto } from './dto/search.dto';

/**
 * GET /v1/search?q=&spaceId=&limit= — core search only supports
 * limit/offset, so meta.nextCursor is always null (single-page result).
 */
@UseGuards(JwtAuthGuard)
@UseFilters(V1ExceptionFilter)
@Controller('v1/search')
export class SearchController {
  constructor(
    private readonly searchService: SearchService,
    private readonly spaceAbility: SpaceAbilityFactory,
  ) {}

  @Get('/')
  async search(
    @Query() dto: V1SearchDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    if (dto.spaceId) {
      const ability = await this.spaceAbility.createForUser(user, dto.spaceId);
      if (ability.cannot(SpaceCaslAction.Read, SpaceCaslSubject.Page)) {
        throw new ForbiddenException();
      }
    }

    const result = await this.searchService.searchPage(
      {
        query: dto.q,
        spaceId: dto.spaceId,
        limit: dto.limit,
      } as any,
      { userId: user.id, workspaceId: workspace.id },
    );

    return {
      data: result.items.map((item: any) => ({
        pageId: item.id,
        title: item.title,
        spaceId: item.space?.id ?? item.spaceId,
        snippet: item.highlight,
      })),
      meta: { nextCursor: null },
    };
  }
}
