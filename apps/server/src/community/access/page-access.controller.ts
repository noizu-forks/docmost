import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  HttpCode,
  HttpStatus,
  NotFoundException,
  Param,
  Patch,
  Post,
  Put,
  Query,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { AuthUser } from '../../common/decorators/auth-user.decorator';
import { AuthWorkspace } from '../../common/decorators/auth-workspace.decorator';
import { Page, User, Workspace } from '@docmost/db/types/entity.types';
import { PageRepo } from '@docmost/db/repos/page/page.repo';
import { PagePermissionRepo } from '@docmost/db/repos/page/page-permission.repo';
import { UserRepo } from '@docmost/db/repos/user/user.repo';
import { GroupRepo } from '@docmost/db/repos/group/group.repo';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PageAccessService } from '../../core/page/page-access/page-access.service';
import { PageAccessLevel, PagePermissionRole } from '../../common/helpers/types/permission';
import { V1PaginationDto } from '../dto/v1-pagination.dto';
import { toDataEnvelope, toPaginationOptions } from '../pagination';
import { V1ExceptionFilter } from '../http/error-filter';
import { GrantsMapper, V1Grant } from './grants.mapper';
import {
  PatchV1GrantDto,
  PostV1GrantsDto,
  PutV1RestrictionDto,
  V1GrantInputDto,
} from './dto/page-access.dto';
import { SkipTransform } from '../../common/decorators/skip-transform.decorator';

/**
 * v1 page access — the restriction + grants surface over the existing
 * page_access/page_permissions data layer (20260224 migration). Grants use
 * stable page_permissions.id (principle 8).
 */
@UseGuards(JwtAuthGuard)
@UseFilters(V1ExceptionFilter)
@Controller('v1/pages')
export class PageAccessController {
  constructor(
    private readonly pageRepo: PageRepo,
    private readonly pagePermissionRepo: PagePermissionRepo,
    private readonly pageAccessService: PageAccessService,
    private readonly grantsMapper: GrantsMapper,
    private readonly userRepo: UserRepo,
    private readonly groupRepo: GroupRepo,
  ) {}

  @SkipTransform()
  @Get(':pageId/access')
  async getAccess(
    @Param('pageId') pageId: string,
    @Query() pagination: V1PaginationDto,
    @AuthUser() user: User,
  ) {
    const page = await this.findPageOrThrow(pageId);

    const pageAccess =
      await this.pagePermissionRepo.findPageAccessByPageId(page.id);

    let restriction: 'none' | 'direct' | 'inherited' = 'none';
    if (pageAccess) {
      restriction = 'direct';
    } else if (await this.pagePermissionRepo.findRestrictedAncestor(page.id)) {
      restriction = 'inherited';
    }

    let canAccess = false;
    let canEdit = false;
    try {
      const result =
        await this.pageAccessService.validateCanViewWithPermissions(page, user);
      canAccess = true;
      canEdit = result.canEdit;
    } catch {
      // Caller cannot view the page (not a space member or restricted).
    }

    let grants: { data: V1Grant[]; meta: { nextCursor: string | null } } = {
      data: [],
      meta: { nextCursor: null },
    };

    if (pageAccess) {
      const result = await this.grantsMapper.listGrants(
        pageAccess.id,
        toPaginationOptions(pagination.limit, pagination.cursor),
      );
      grants = toDataEnvelope(result);
    }

    return { restriction, canAccess, canEdit, grants };
  }

  @SkipTransform()
  @Put(':pageId/access/restriction')
  async putRestriction(
    @Param('pageId') pageId: string,
    @Body() dto: PutV1RestrictionDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const page = await this.findEditablePageOrThrow(pageId, user);

    if (!dto.restricted) {
      await this.pagePermissionRepo.deletePageAccess(page.id);
      return { restriction: 'none' as const };
    }

    const existing =
      await this.pagePermissionRepo.findPageAccessByPageId(page.id);
    if (!existing) {
      await this.pagePermissionRepo.insertPageAccess({
        pageId: page.id,
        workspaceId: workspace.id,
        spaceId: page.spaceId,
        accessLevel: PageAccessLevel.RESTRICTED,
        creatorId: user.id,
      });
    }

    return { restriction: 'direct' as const };
  }

  @SkipTransform()
  @Post(':pageId/access/grants')
  async postGrants(
    @Param('pageId') pageId: string,
    @Body() dto: PostV1GrantsDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const page = await this.findEditablePageOrThrow(pageId, user);
    const pageAccess = await this.ensurePageAccess(page, user, workspace);

    // Reject unknown principals with a clean 4xx instead of a raw FK 500.
    await this.validatePrincipals(dto.grants, workspace.id);

    await this.pagePermissionRepo.insertPagePermissions(
      GrantsMapper.toGrantRows(pageAccess.id, dto.grants, user.id),
    );

    // Return the full grant set for the page.
    return this.listAllGrants(pageAccess.id);
  }

  /** Every grant principal must exist in this workspace (clean 400 otherwise). */
  private async validatePrincipals(
    grants: V1GrantInputDto[],
    workspaceId: string,
  ) {
    const missing: string[] = [];
    for (const grant of grants) {
      const exists =
        grant.type === 'user'
          ? Boolean(await this.userRepo.findById(grant.principalId, workspaceId))
          : Boolean(await this.groupRepo.findById(grant.principalId, workspaceId));
      if (!exists) missing.push(grant.principalId);
    }
    if (missing.length > 0) {
      throw new BadRequestException(
        `Unknown ${missing.length === 1 ? 'principal' : 'principals'}: ${missing.join(', ')}`,
      );
    }
  }

  @SkipTransform()
  @Patch(':pageId/access/grants/:grantId')
  async patchGrant(
    @Param('pageId') pageId: string,
    @Param('grantId') grantId: string,
    @Body() dto: PatchV1GrantDto,
    @AuthUser() user: User,
  ) {
    const page = await this.findEditablePageOrThrow(pageId, user);
    const pageAccess =
      await this.pagePermissionRepo.findPageAccessByPageId(page.id);
    if (!pageAccess) {
      throw new NotFoundException('Page is not restricted');
    }

    await this.grantsMapper.updateRoleById(grantId, pageAccess.id, dto.role);

    return this.grantsMapper.findGrantById(grantId);
  }

  @HttpCode(HttpStatus.NO_CONTENT)
  @SkipTransform()
  @Delete(':pageId/access/grants/:grantId')
  async deleteGrant(
    @Param('pageId') pageId: string,
    @Param('grantId') grantId: string,
    @AuthUser() user: User,
  ) {
    const page = await this.findEditablePageOrThrow(pageId, user);
    const pageAccess =
      await this.pagePermissionRepo.findPageAccessByPageId(page.id);
    if (!pageAccess) {
      return; // idempotent 204: no restriction means no grants
    }

    await this.grantsMapper.deleteById(grantId, pageAccess.id);
  }

  private async listAllGrants(pageAccessId: string) {
    const result = await this.grantsMapper.listGrants(
      pageAccessId,
      toPaginationOptions(100),
    );

    return toDataEnvelope(result);
  }

  private async findPageOrThrow(pageId: string): Promise<Page> {
    if (!pageId) {
      throw new BadRequestException('pageId is required');
    }
    const page = await this.pageRepo.findById(pageId);
    if (!page) {
      throw new NotFoundException('Page not found');
    }
    return page;
  }

  private async findEditablePageOrThrow(
    pageId: string,
    user: User,
  ): Promise<Page> {
    const page = await this.findPageOrThrow(pageId);
    await this.pageAccessService.validateCanEdit(page, user);
    return page;
  }

  private async ensurePageAccess(
    page: Page,
    user: User,
    workspace: Workspace,
  ) {
    const pageAccess =
      await this.pagePermissionRepo.findPageAccessByPageId(page.id);
    if (pageAccess) {
      return pageAccess;
    }

    return this.pagePermissionRepo.insertPageAccess({
      pageId: page.id,
      workspaceId: workspace.id,
      spaceId: page.spaceId,
      accessLevel: PageAccessLevel.RESTRICTED,
      creatorId: user.id,
    });
  }
}
