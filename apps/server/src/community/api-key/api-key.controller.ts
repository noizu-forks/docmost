import {
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { AuthUser } from '../../common/decorators/auth-user.decorator';
import { AuthWorkspace } from '../../common/decorators/auth-workspace.decorator';
import { User, Workspace } from '@docmost/db/types/entity.types';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import WorkspaceAbilityFactory from '../../core/casl/abilities/workspace-ability.factory';
import {
  WorkspaceCaslAction,
  WorkspaceCaslSubject,
} from '../../core/casl/interfaces/workspace-ability.type';
import { ApiKeyService } from './api-key.service';
import { ApiKeyIdDto, CreateApiKeyDto } from './dto/api-key.dto';

/**
 * Community API key management. Keys authenticate with
 * `Authorization: Bearer <token>`; the raw token is returned exactly once
 * on mint and is never persisted or listed again.
 */
@UseGuards(JwtAuthGuard)
@Controller('keys')
export class ApiKeyController {
  constructor(
    private readonly apiKeyService: ApiKeyService,
    private readonly workspaceAbility: WorkspaceAbilityFactory,
  ) {}

  @HttpCode(HttpStatus.OK)
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
  async listApiKeys(@AuthUser() user: User, @AuthWorkspace() workspace: Workspace) {
    this.assertApiAdmin(user, workspace);

    // Tokens are stateless JWTs and are never stored, so rows carry no secret.
    return { items: await this.apiKeyService.listApiKeys(workspace.id) };
  }

  @Delete('/:id')
  async revokeApiKey(
    @Param() apiKeyIdDto: ApiKeyIdDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    this.assertApiAdmin(user, workspace);

    await this.apiKeyService.revokeApiKey(apiKeyIdDto.id, workspace.id);
  }

  private assertApiAdmin(user: User, workspace: Workspace) {
    const ability = this.workspaceAbility.createForUser(user, workspace);
    if (ability.cannot(WorkspaceCaslAction.Manage, WorkspaceCaslSubject.API)) {
      throw new ForbiddenException();
    }
  }
}
