import {
  BadRequestException,
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
import { SkipTransform } from '../../common/decorators/skip-transform.decorator';

/**
 * GET /v1/search?q=&spaceId=&limit=&cursor= — core search only supports
 * limit/offset (rank-ordered), so the cursor is an opaque base64 offset.
 * Fetches limit+1 rows to detect the next page without a count query.
 */
@UseGuards(JwtAuthGuard)
@UseFilters(V1ExceptionFilter)
@Controller('v1/search')
export class SearchController {
  constructor(
    private readonly searchService: SearchService,
    private readonly spaceAbility: SpaceAbilityFactory,
  ) {}

  @SkipTransform()
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

    const limit = dto.limit ?? 20;
    const offset = decodeOffsetCursor(dto.cursor);

    const result = await this.searchService.searchPage(
      {
        query: dto.q,
        spaceId: dto.spaceId,
        limit: limit + 1,
        offset,
      } as any,
      { userId: user.id, workspaceId: workspace.id },
    );

    const page = result.items.slice(0, limit);
    const hasNext = result.items.length > limit;

    return {
      data: page.map((item: any) => ({
        pageId: item.id,
        title: item.title,
        spaceId: item.space?.id ?? item.spaceId,
        snippet: item.highlight,
      })),
      meta: {
        nextCursor: hasNext ? encodeOffsetCursor(offset + limit) : null,
      },
    };
  }
}

function encodeOffsetCursor(offset: number): string {
  return Buffer.from(`offset:${offset}`).toString('base64url');
}

function decodeOffsetCursor(cursor?: string): number {
  if (!cursor) return 0;
  try {
    const decoded = Buffer.from(cursor, 'base64url').toString('utf8');
    const match = /^offset:(\d+)$/.exec(decoded);
    if (match) return Number(match[1]);
  } catch {
    // fall through
  }
  throw new BadRequestException('Invalid cursor');
}
