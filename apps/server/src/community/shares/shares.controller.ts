import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  HttpCode,
  HttpStatus,
  NotFoundException,
  Param,
  Put,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { AuthUser } from '../../common/decorators/auth-user.decorator';
import { AuthWorkspace } from '../../common/decorators/auth-workspace.decorator';
import { User, Workspace } from '@docmost/db/types/entity.types';
import { PageRepo } from '@docmost/db/repos/page/page.repo';
import { ShareRepo } from '@docmost/db/repos/share/share.repo';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PageAccessService } from '../../core/page/page-access/page-access.service';
import { PagePermissionRepo } from '@docmost/db/repos/page/page-permission.repo';
import { ShareService } from '../../core/share/share.service';
import { EnvironmentService } from '../../integrations/environment/environment.service';
import { V1ExceptionFilter } from '../http/error-filter';
import { PutV1ShareDto } from './dto/share.dto';
import { SkipTransform } from '../../common/decorators/skip-transform.decorator';

/**
 * One share upsert per page (principle 6): GET returns the effective share
 * (closest shared ancestor) with a server-computed publicUrl (principle 7);
 * PUT with {shared:false} deletes.
 */
@UseGuards(JwtAuthGuard)
@UseFilters(V1ExceptionFilter)
@Controller('v1/pages')
export class SharesController {
  constructor(
    private readonly shareService: ShareService,
    private readonly shareRepo: ShareRepo,
    private readonly pageRepo: PageRepo,
    private readonly pagePermissionRepo: PagePermissionRepo,
    private readonly pageAccessService: PageAccessService,
    private readonly environmentService: EnvironmentService,
  ) {}

  @SkipTransform()
  @Get(':pageId/share')
  async getShare(
    @Param('pageId') pageId: string,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const share = await this.shareService.getShareForPage(
      pageId,
      workspace.id,
    );

    if (!share) {
      return { shared: false };
    }

    return {
      shared: true,
      key: share.key,
      includeSubPages: share.includeSubPages,
      searchIndexing: share.searchIndexing,
      level: share.level,
      publicUrl: this.buildPublicUrl(share.key),
    };
  }

  @SkipTransform()
  @Put(':pageId/share')
  async putShare(
    @Param('pageId') pageId: string,
    @Body() dto: PutV1ShareDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const page = await this.pageRepo.findById(pageId);
    if (!page || page.workspaceId !== workspace.id) {
      throw new NotFoundException('Page not found');
    }

    if (!dto.shared) {
      const existing = await this.shareService.getShareForPage(
        page.id,
        workspace.id,
      );
      if (existing) {
        await this.shareRepo.deleteShare(existing.id);
      }
      return { shared: false };
    }

    // All core guards kept: editor permission, restricted-ancestor block,
    // workspace/space sharing enabled.
    await this.pageAccessService.validateCanEdit(page, user);

    const isRestricted = await this.pagePermissionRepo.hasRestrictedAncestor(
      page.id,
    );
    if (isRestricted) {
      throw new ForbiddenException('Cannot share a restricted page');
    }

    const sharingAllowed = await this.shareService.isSharingAllowed(
      workspace.id,
      page.spaceId,
    );
    if (!sharingAllowed) {
      throw new ForbiddenException('Public sharing is disabled');
    }

    const existingShare = await this.shareService.getShareForPage(
      page.id,
      workspace.id,
    );

    let key: string;
    let includeSubPages: boolean;
    let searchIndexing: boolean;
    if (existingShare && existingShare.level === 0) {
      await this.shareService.updateShare(existingShare.id, {
        shareId: existingShare.id,
        pageId,
        includeSubPages: dto.includeSubPages,
        searchIndexing: dto.searchIndexing,
      } as any);
      key = existingShare.key;
      includeSubPages = dto.includeSubPages ?? existingShare.includeSubPages;
      searchIndexing = dto.searchIndexing ?? existingShare.searchIndexing;
    } else {
      const created = await this.shareService.createShare({
        page,
        authUserId: user.id,
        workspaceId: workspace.id,
        createShareDto: {
          pageId: page.id,
          includeSubPages: dto.includeSubPages,
          searchIndexing: dto.searchIndexing,
        },
      });
      key = created.key;
      includeSubPages = dto.includeSubPages ?? created.includeSubPages ?? false;
      searchIndexing = dto.searchIndexing ?? created.searchIndexing ?? false;
    }

    return {
      shared: true,
      key,
      includeSubPages,
      searchIndexing,
      level: 0,
      publicUrl: this.buildPublicUrl(key),
    };
  }

  private buildPublicUrl(shareKey: string): string {
    const appUrl = this.environmentService.getAppUrl().replace(/\/$/, '');
    return `${appUrl}/share/${shareKey}`;
  }
}
