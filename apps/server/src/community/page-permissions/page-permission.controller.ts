import {
  BadRequestException,
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  NotFoundException,
  Post,
  UseGuards,
} from '@nestjs/common';
import { AuthUser } from '../../common/decorators/auth-user.decorator';
import { AuthWorkspace } from '../../common/decorators/auth-workspace.decorator';
import { Page, User, Workspace } from '@docmost/db/types/entity.types';
import { PageRepo } from '@docmost/db/repos/page/page.repo';
import { PagePermissionRepo } from '@docmost/db/repos/page/page-permission.repo';
import { PageAccessService } from '../../core/page/page-access/page-access.service';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PageAccessLevel } from '../../common/helpers/types/permission';
import {
  AddPagePermissionDto,
  GetPagePermissionInfoDto,
  GetPagePermissionsDto,
  PagePermissionEntry,
  RemovePagePermissionDto,
  RestrictPageDto,
  UpdatePagePermissionDto,
} from './page-permission.dto';

/**
 * Community page-permission management. The client contract is POST with
 * JSON bodies; response shapes are the acceptance contract:
 *   permission-info -> {hasDirectRestriction, hasInheritedRestriction, canAccess, canEdit, permissions: []}
 *   permissions     -> {permissions: [{type, id, role}], meta: {nextCursor}}
 */
@UseGuards(JwtAuthGuard)
@Controller('pages')
export class PagePermissionController {
  constructor(
    private readonly pageRepo: PageRepo,
    private readonly pagePermissionRepo: PagePermissionRepo,
    private readonly pageAccessService: PageAccessService,
  ) {}

  @HttpCode(HttpStatus.OK)
  @Post('permission-info')
  async getPermissionInfo(
    @Body() dto: GetPagePermissionInfoDto,
    @AuthUser() user: User,
  ) {
    const page = await this.findPageOrThrow(dto.pageId);

    const pageAccess =
      await this.pagePermissionRepo.findPageAccessByPageId(page.id);

    let hasInheritedRestriction = false;
    if (!pageAccess) {
      const restrictedAncestor =
        await this.pagePermissionRepo.findRestrictedAncestor(page.id);
      hasInheritedRestriction = !!restrictedAncestor;
    }

    let canAccess = false;
    let canEdit = false;
    try {
      const { canEdit: canEditPage } =
        await this.pageAccessService.validateCanViewWithPermissions(page, user);
      canAccess = true;
      canEdit = canEditPage;
    } catch {
      // Caller cannot view the page (not a space member or restricted).
    }

    return {
      hasDirectRestriction: !!pageAccess,
      hasInheritedRestriction,
      canAccess,
      canEdit,
      permissions: [] as PagePermissionEntry[],
    };
  }

  @HttpCode(HttpStatus.OK)
  @Post('permissions')
  async getPermissions(
    @Body() dto: GetPagePermissionsDto,
    @AuthUser() user: User,
  ) {
    await this.findPageOrThrow(dto.pageId);

    const pageAccess = await this.pagePermissionRepo.findPageAccessByPageId(
      dto.pageId,
    );
    if (!pageAccess) {
      return {
        permissions: [] as PagePermissionEntry[],
        meta: { hasNextPage: false, nextCursor: null },
      };
    }

    const result = await this.pagePermissionRepo.getPagePermissionsPaginated(
      pageAccess.id,
      dto,
    );

    let permissions: PagePermissionEntry[] = result.items.map((member) => ({
      type: member.type,
      id: member.id,
      role: member.role as PagePermissionEntry['role'],
    }));

    if (dto.userIds || dto.groupIds) {
      permissions = permissions.filter(
        (permission) =>
          (permission.type === 'user' && dto.userIds?.includes(permission.id)) ||
          (permission.type === 'group' &&
            dto.groupIds?.includes(permission.id)),
      );
    }

    return {
      permissions,
      meta: { nextCursor: result.meta.hasNextPage ? result.meta.nextCursor : null },
    };
  }

  @HttpCode(HttpStatus.OK)
  @Post('restrict')
  async restrictPage(
    @Body() dto: RestrictPageDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const page = await this.findEditablePageOrThrow(dto.pageId, user);

    const existingAccess = await this.pagePermissionRepo.findPageAccessByPageId(
      page.id,
    );
    if (existingAccess) {
      return existingAccess;
    }

    return this.pagePermissionRepo.insertPageAccess({
      pageId: page.id,
      workspaceId: workspace.id,
      spaceId: page.spaceId,
      accessLevel: PageAccessLevel.RESTRICTED,
      creatorId: user.id,
    });
  }

  @HttpCode(HttpStatus.OK)
  @Post('remove-restriction')
  async removeRestriction(
    @Body() dto: RestrictPageDto,
    @AuthUser() user: User,
  ) {
    const page = await this.findEditablePageOrThrow(dto.pageId, user);

    const pageAccess = await this.pagePermissionRepo.findPageAccessByPageId(
      page.id,
    );
    if (!pageAccess) {
      throw new NotFoundException('Page is not restricted');
    }

    await this.pagePermissionRepo.deletePageAccess(page.id);
  }

  @HttpCode(HttpStatus.OK)
  @Post('add-permission')
  async addPermission(
    @Body() dto: AddPagePermissionDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const page = await this.findEditablePageOrThrow(dto.pageId, user);

    if (!dto.userIds && !dto.groupIds) {
      throw new BadRequestException('userIds or groupIds is required');
    }

    const pageAccess = await this.ensurePageAccess(page, user, workspace);

    const permissions = [
      ...(dto.userIds ?? []).map((userId) => ({
        pageAccessId: pageAccess.id,
        userId,
        role: dto.role,
        addedById: user.id,
      })),
      ...(dto.groupIds ?? []).map((groupId) => ({
        pageAccessId: pageAccess.id,
        groupId,
        role: dto.role,
        addedById: user.id,
      })),
    ];

    await this.pagePermissionRepo.insertPagePermissions(permissions);
  }

  @HttpCode(HttpStatus.OK)
  @Post('update-permission')
  async updatePermission(
    @Body() dto: UpdatePagePermissionDto,
    @AuthUser() user: User,
  ) {
    const page = await this.findEditablePageOrThrow(dto.pageId, user);

    if (!dto.userId && !dto.groupId) {
      throw new BadRequestException('userId or groupId is required');
    }

    const pageAccess = await this.pagePermissionRepo.findPageAccessByPageId(
      page.id,
    );
    if (!pageAccess) {
      throw new NotFoundException('Page is not restricted');
    }

    await this.pagePermissionRepo.updatePagePermissionRole(
      pageAccess.id,
      dto.role,
      { userId: dto.userId, groupId: dto.groupId },
    );
  }

  @HttpCode(HttpStatus.OK)
  @Post('remove-permission')
  async removePermission(
    @Body() dto: RemovePagePermissionDto,
    @AuthUser() user: User,
  ) {
    const page = await this.findEditablePageOrThrow(dto.pageId, user);

    if (!dto.userIds && !dto.groupIds) {
      throw new BadRequestException('userIds or groupIds is required');
    }

    const pageAccess = await this.pagePermissionRepo.findPageAccessByPageId(
      page.id,
    );
    if (!pageAccess) {
      throw new NotFoundException('Page is not restricted');
    }

    if (dto.userIds?.length) {
      await this.pagePermissionRepo.deletePagePermissionsByUserIds(
        pageAccess.id,
        dto.userIds,
      );
    }

    if (dto.groupIds?.length) {
      await this.pagePermissionRepo.deletePagePermissionsByGroupIds(
        pageAccess.id,
        dto.groupIds,
      );
    }
  }

  private async findPageOrThrow(pageId: string): Promise<Page> {
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
    const pageAccess = await this.pagePermissionRepo.findPageAccessByPageId(
      page.id,
    );
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
