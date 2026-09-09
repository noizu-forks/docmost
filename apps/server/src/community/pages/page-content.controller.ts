import {
  Body,
  Controller,
  NotFoundException,
  Param,
  Put,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { AuthUser } from '../../common/decorators/auth-user.decorator';
import { Page, User } from '@docmost/db/types/entity.types';
import { PageRepo } from '@docmost/db/repos/page/page.repo';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PageAccessService } from '../../core/page/page-access/page-access.service';
import { PageService } from '../../core/page/services/page.service';
import { jsonToHtml, jsonToMarkdown } from '../../collaboration/collaboration.util';
import { V1ExceptionFilter } from '../http/error-filter';
import { PutV1PageContentDto } from './dto/page.dto';
import { SkipTransform } from '../../common/decorators/skip-transform.decorator';

/**
 * PUT /v1/pages/:pageId/content — full content write with optional
 * append/prepend operation (default replace). Markdown-first (principle 5).
 */
@UseGuards(JwtAuthGuard)
@UseFilters(V1ExceptionFilter)
@Controller('v1/pages')
export class PageContentController {
  constructor(
    private readonly pageService: PageService,
    private readonly pageRepo: PageRepo,
    private readonly pageAccessService: PageAccessService,
  ) {}

  @SkipTransform()
  @Put(':pageId/content')
  async putContent(
    @Param('pageId') pageId: string,
    @Body() dto: PutV1PageContentDto,
    @AuthUser() user: User,
  ) {
    const page = await this.pageRepo.findById(pageId);
    if (!page) {
      throw new NotFoundException('Page not found');
    }

    const { hasRestriction } = await this.pageAccessService.validateCanEdit(
      page,
      user,
    );

    const updatedPage: Page = await this.pageService.update(
      page,
      {
        pageId,
        content: dto.content,
        operation: dto.operation ?? 'replace',
        format: dto.format ?? 'markdown',
      } as any,
      user,
    );

    const result: any = {
      ...updatedPage,
      permissions: { canEdit: true, hasRestriction },
    };

    const format = dto.format ?? 'markdown';
    if (format !== 'json' && updatedPage.content) {
      result.content =
        format === 'html'
          ? jsonToHtml(updatedPage.content)
          : jsonToMarkdown(updatedPage.content);
    }

    return result;
  }
}
