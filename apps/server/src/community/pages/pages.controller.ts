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
  Query,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { AuthUser } from '../../common/decorators/auth-user.decorator';
import { AuthWorkspace } from '../../common/decorators/auth-workspace.decorator';
import { Page, User, Workspace } from '@docmost/db/types/entity.types';
import { PageRepo } from '@docmost/db/repos/page/page.repo';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PageAccessService } from '../../core/page/page-access/page-access.service';
import { PageService } from '../../core/page/services/page.service';
import SpaceAbilityFactory from '../../core/casl/abilities/space-ability.factory';
import {
  SpaceCaslAction,
  SpaceCaslSubject,
} from '../../core/casl/interfaces/space-ability.type';
import { jsonToHtml, jsonToMarkdown } from '../../collaboration/collaboration.util';
import { V1PaginationDto } from '../dto/v1-pagination.dto';
import { toDataEnvelope, toPaginationOptions } from '../pagination';
import { V1ExceptionFilter } from '../http/error-filter';
import {
  CreateV1PageDto,
  DeleteV1PageDto,
  PatchV1PageDto,
} from './dto/page.dto';
import { SkipTransform } from '../../common/decorators/skip-transform.decorator';

/**
 * v1 pages: page resources inside a space (list/create) and single-page
 * operations (get/patch/delete/restore/children/breadcrumbs). Thin facade
 * over PageService/PageRepo with the same CASL checks as core.
 */
@UseGuards(JwtAuthGuard)
@UseFilters(V1ExceptionFilter)
@Controller()
export class PagesController {
  constructor(
    private readonly pageService: PageService,
    private readonly pageRepo: PageRepo,
    private readonly pageAccessService: PageAccessService,
    private readonly spaceAbility: SpaceAbilityFactory,
  ) {}

  // --- space-scoped ---

  @SkipTransform()
  @Get('v1/spaces/:spaceId/pages')
  async listSpacePages(
    @Param('spaceId') spaceId: string,
    @Query('parentId') parentId: string | undefined,
    @Query() pagination: V1PaginationDto,
    @AuthUser() user: User,
  ) {
    const ability = await this.spaceAbility.createForUser(user, spaceId);
    if (ability.cannot(SpaceCaslAction.Read, SpaceCaslSubject.Page)) {
      throw new ForbiddenException();
    }

    const spaceCanEdit = ability.can(SpaceCaslAction.Edit, SpaceCaslSubject.Page);

    const result = await this.pageService.getSidebarPages(
      spaceId,
      toPaginationOptions(pagination.limit, pagination.cursor),
      parentId,
      user.id,
      spaceCanEdit,
    );

    return toDataEnvelope(result);
  }

  @SkipTransform()
  @Post('v1/spaces/:spaceId/pages')
  async createPage(
    @Param('spaceId') spaceId: string,
    @Body() dto: CreateV1PageDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    if (dto.parentId) {
      const parentPage = await this.pageRepo.findById(dto.parentId);
      if (
        !parentPage ||
        parentPage.deletedAt ||
        parentPage.spaceId !== spaceId
      ) {
        throw new NotFoundException('Parent page not found');
      }
      await this.pageAccessService.validateCanEdit(parentPage, user);
    } else {
      const ability = await this.spaceAbility.createForUser(user, spaceId);
      if (ability.cannot(SpaceCaslAction.Create, SpaceCaslSubject.Page)) {
        throw new ForbiddenException();
      }
    }

    // the v1 contract is markdown-first (principle 5): default the stored
    // format AND the response representation.
    const format = dto.format ?? 'markdown';

    const created = await this.pageService.create(user.id, workspace.id, {
      title: dto.title,
      content: dto.content,
      parentPageId: dto.parentId,
      spaceId,
      // core's create() only processes content when a format is present;
      // the v1 contract is markdown-first (principle 5), so default it.
      format,
    } as any);

    // insertPage() returns baseFields only — re-fetch so the create
    // response carries content in the same shape as GET (the v1 client
    // encodes this response directly).
    const page = await this.pageRepo.findById(created.id, {
      includeSpace: true,
      includeContent: true,
    });
    return this.formatContent(page, format);
  }

  // --- page-scoped ---

  @SkipTransform()
  @Get('v1/pages/:pageId')
  async getPage(
    @Param('pageId') pageId: string,
    @Query() query: { format?: string; include?: string },
    @AuthUser() user: User,
  ) {
    const page = await this.pageRepo.findById(pageId, {
      includeSpace: true,
      includeContent: true,
      includeCreator: true,
      includeLastUpdatedBy: true,
    });

    if (!page) {
      throw new NotFoundException('Page not found');
    }

    const { canEdit, hasRestriction } =
      await this.pageAccessService.validateCanViewWithPermissions(page, user);

    const result: any = {
      ...page,
      permissions: { canEdit, hasRestriction },
    };

    const includes = (query.include ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);

    // markdown-first (principle 5): explicit ?format=opt-in, default markdown.
    const format = query.format ?? 'markdown';
    if (format !== 'json' && page.content) {
      result.content =
        format === 'html'
          ? jsonToHtml(page.content)
          : jsonToMarkdown(page.content);
    }

    if (includes.includes('children')) {
      const children = await this.pageService.getSidebarPages(
        page.spaceId,
        toPaginationOptions(100),
        page.id,
        user.id,
        canEdit,
      );
      result.children = children.items;
    }

    if (includes.includes('breadcrumbs')) {
      result.breadcrumbs = await this.pageService.getPageBreadCrumbs(page.id);
    }

    return result;
  }

  @SkipTransform()
  @Get('v1/pages/:pageId/children')
  async getChildren(
    @Param('pageId') pageId: string,
    @Query() pagination: V1PaginationDto,
    @AuthUser() user: User,
  ) {
    const page = await this.findPageOrThrow(pageId);

    const ability = await this.spaceAbility.createForUser(user, page.spaceId);
    if (ability.cannot(SpaceCaslAction.Read, SpaceCaslSubject.Page)) {
      throw new ForbiddenException();
    }

    const spaceCanEdit = ability.can(SpaceCaslAction.Edit, SpaceCaslSubject.Page);

    const result = await this.pageService.getSidebarPages(
      page.spaceId,
      toPaginationOptions(pagination.limit, pagination.cursor),
      page.id,
      user.id,
      spaceCanEdit,
    );

    return toDataEnvelope(result);
  }

  @SkipTransform()
  @Get('v1/pages/:pageId/breadcrumbs')
  async getBreadcrumbs(
    @Param('pageId') pageId: string,
    @AuthUser() user: User,
  ) {
    const page = await this.findPageOrThrow(pageId);

    await this.pageAccessService.validateCanView(page, user);

    return {
      data: await this.pageService.getPageBreadCrumbs(page.id),
    };
  }

  @SkipTransform()
  @Patch('v1/pages/:pageId')
  async patchPage(
    @Param('pageId') pageId: string,
    @Body() dto: PatchV1PageDto,
    @AuthUser() user: User,
  ) {
    const page = await this.findPageOrThrow(pageId);
    await this.pageAccessService.validateCanEdit(page, user);

    if (dto.title !== undefined) {
      await this.pageService.update(page, { pageId, title: dto.title }, user);
    }

    if (dto.parentId !== undefined && dto.parentId !== page.parentPageId) {
      // parentId change = move. Same checks as core's move endpoint.
      if (dto.parentId) {
        const targetParent = await this.pageRepo.findById(dto.parentId);
        if (!targetParent || targetParent.deletedAt) {
          throw new NotFoundException('Target parent page not found');
        }
        if (targetParent.spaceId !== page.spaceId) {
          throw new BadRequestException('Target parent is in a different space');
        }
        await this.pageAccessService.validateCanEdit(targetParent, user);
      }

      // Append to the end of the new parent's children.
      await this.pageService.movePage(
        {
          pageId: page.id,
          parentPageId: dto.parentId,
          // Position is an internal fractional-index key; moving without an
          // explicit position appends after the current page's own key.
          position: page.position as any,
        } as any,
        page,
      );
      return this.formatContent(
        await this.pageRepo.findById(pageId, {
          includeSpace: true,
          includeContent: true,
        }),
        'markdown',
      );
    }

    return this.formatContent(
      await this.pageRepo.findById(pageId, {
        includeSpace: true,
        includeContent: true,
      }),
      'markdown',
    );
  }

  @HttpCode(HttpStatus.NO_CONTENT)
  @SkipTransform()
  @Delete('v1/pages/:pageId')
  async deletePage(
    @Param('pageId') pageId: string,
    @Query() query: DeleteV1PageDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const page = await this.pageRepo.findById(pageId);
    if (!page) {
      return; // idempotent 204
    }

    const ability = await this.spaceAbility.createForUser(user, page.spaceId);

    if (query?.permanent === 'true') {
      if (ability.cannot(SpaceCaslAction.Manage, SpaceCaslSubject.Settings)) {
        throw new ForbiddenException(
          'Only space admins can permanently delete pages',
        );
      }
      await this.pageService.forceDelete(pageId, workspace.id);
      return;
    }

    await this.pageAccessService.validateCanEdit(page, user);
    await this.pageService.removePage(pageId, user.id, workspace.id);
  }

  @SkipTransform()
  @Post('v1/pages/:pageId/restore')
  async restorePage(
    @Param('pageId') pageId: string,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const page = await this.pageRepo.findById(pageId);
    if (!page) {
      throw new NotFoundException('Page not found');
    }

    const ability = await this.spaceAbility.createForUser(user, page.spaceId);
    if (ability.cannot(SpaceCaslAction.Edit, SpaceCaslSubject.Page)) {
      throw new ForbiddenException();
    }

    await this.pageAccessService.validateCanEdit(page, user);

    await this.pageRepo.restorePage(pageId, workspace.id);

    return this.formatContent(
      await this.pageRepo.findById(pageId, {
        includeSpace: true,
        includeContent: true,
      }),
      'markdown',
    );
  }

  private async findPageOrThrow(pageId: string): Promise<Page> {
    const page = await this.pageRepo.findById(pageId);
    if (!page) {
      throw new NotFoundException('Page not found');
    }
    return page;
  }

  private formatContent(page: Page, format?: string) {
    if (format && format !== 'json' && page.content) {
      return {
        ...page,
        content:
          format === 'html' ? jsonToHtml(page.content) : jsonToMarkdown(page.content),
      };
    }
    return page;
  }
}
