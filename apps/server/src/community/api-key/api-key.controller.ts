import {
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  HttpCode,
  Param,
  Post,
  Query,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import { HttpStatus } from '@nestjs/common';
import { AuthUser } from '../../common/decorators/auth-user.decorator';
import { AuthWorkspace } from '../../common/decorators/auth-workspace.decorator';
import { User, Workspace } from '@docmost/db/types/entity.types';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import WorkspaceAbilityFactory from '../../core/casl/abilities/workspace-ability.factory';
import {
  WorkspaceCaslAction,
  WorkspaceCaslSubject,
} from '../../core/casl/interfaces/workspace-ability.type';
import { V1PaginationDto } from '../dto/v1-pagination.dto';
import { toDataEnvelope, toPaginationOptions } from '../pagination';
import { V1ExceptionFilter } from '../http/error-filter';
import { ApiKeyService } from './api-key.service';
import { CreateApiKeyDto } from './dto/api-key.dto';

/**
 * v1 API key management (admin only; WorkspaceCaslAction.Manage on API).
 * Keys authenticate with `Authorization: Bearer <token>`; the raw token is
 * returned exactly once on mint and is never persisted or listed again.
 */
@UseGuards(JwtAuthGuard)
@UseFilters(V1ExceptionFilter)
@Controller('v1/keys')
export class ApiKeyController {
  constructor(
    private readonly apiKeyService: ApiKeyService,
    private readonly workspaceAbility: WorkspaceAbilityFactory,
  ) {}

  @Post('/')
  async createApiKey(
    @Body() createApiKeyDto: CreateApiKeyDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    this.assertApiAdmin(user, workspace);

    return this.apiKeyService.createApiKey(
      createApiKeyDto,
      user,
      workspace.id,
    );
  }

  @Get('/')
  async listApiKeys(
    @Query() pagination: V1PaginationDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    this.assertApiAdmin(user, workspace);

    const result = await this.apiKeyService.listApiKeys(
      workspace.id,
      toPaginationOptions(pagination.limit, pagination.cursor),
    );

    // Tokens are stateless JWTs and are never stored, so rows carry no secret.
    return toDataEnvelope({
      ...result,
      items: result.items.map((key) => ({
        id: key.id,
        name: key.name,
        expiresAt: key.expiresAt,
        lastUsedAt: key.lastUsedAt,
        createdAt: key.createdAt,
      })),
    });
  }

  @HttpCode(HttpStatus.NO_CONTENT)
  @Delete('/:keyId')
  async revokeApiKey(
    @Param('keyId') keyId: string,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    this.assertApiAdmin(user, workspace);

    await this.apiKeyService.revokeApiKey(keyId, workspace.id);
  }

  private assertApiAdmin(user: User, workspace: Workspace) {
    const ability = this.workspaceAbility.createForUser(user, workspace);
    if (ability.cannot(WorkspaceCaslAction.Manage, WorkspaceCaslSubject.API)) {
      throw new ForbiddenException();
    }
  }
}
