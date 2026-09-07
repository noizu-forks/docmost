import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { InjectKysely } from 'nestjs-kysely';
import { KyselyDB } from '@docmost/db/types/kysely.types';
import { ApiKey, User, Workspace } from '@docmost/db/types/entity.types';
import { UserRepo } from '@docmost/db/repos/user/user.repo';
import { WorkspaceRepo } from '@docmost/db/repos/workspace/workspace.repo';
import { isUserDisabled } from '../../common/helpers';
import { JwtApiKeyPayload } from '../../core/auth/dto/jwt-payload';
import { TokenService } from '../../core/auth/services/token.service';
import { CreateApiKeyDto } from './dto/api-key.dto';

/**
 * Default API key lifetime. The global JWT expiry (JWT_TOKEN_EXPIRES_IN)
 * must NOT govern API keys — without an explicit expiresIn a minted key
 * would silently stop working when regular tokens expire.
 */
export const API_KEY_DEFAULT_EXPIRES_IN = '10y' as const;

@Injectable()
export class ApiKeyService {
  private logger = new Logger('ApiKeyService');

  constructor(
    @InjectKysely() private readonly db: KyselyDB,
    private readonly tokenService: TokenService,
    private readonly userRepo: UserRepo,
    private readonly workspaceRepo: WorkspaceRepo,
  ) {}

  async createApiKey(
    createApiKeyDto: CreateApiKeyDto,
    user: User,
    workspaceId: string,
  ): Promise<{ id: string; name: string; token: string }> {
    const apiKey = await this.db
      .insertInto('apiKeys')
      .values({
        name: createApiKeyDto.name,
        creatorId: user.id,
        workspaceId,
      })
      .returningAll()
      .executeTakeFirst();

    if (!apiKey) {
      throw new BadRequestException('Failed to create API key');
    }

    const token = await this.tokenService.generateApiToken({
      apiKeyId: apiKey.id,
      user,
      workspaceId,
      expiresIn:
        (createApiKeyDto.expiresIn as any) ?? API_KEY_DEFAULT_EXPIRES_IN,
    });

    // The raw token is only ever returned on mint; it is not persisted.
    return { id: apiKey.id, name: apiKey.name, token };
  }

  async listApiKeys(workspaceId: string): Promise<ApiKey[]> {
    return this.db
      .selectFrom('apiKeys')
      .selectAll()
      .where('workspaceId', '=', workspaceId)
      .where('deletedAt', 'is', null)
      .orderBy('createdAt desc')
      .execute();
  }

  async revokeApiKey(id: string, workspaceId: string): Promise<void> {
    const apiKey = await this.db
      .selectFrom('apiKeys')
      .selectAll()
      .where('id', '=', id)
      .where('workspaceId', '=', workspaceId)
      .executeTakeFirst();

    if (!apiKey) {
      throw new NotFoundException('API key not found');
    }

    await this.db
      .updateTable('apiKeys')
      .set({ deletedAt: new Date(), updatedAt: new Date() })
      .where('id', '=', id)
      .execute();
  }

  async validateApiKey(payload: JwtApiKeyPayload): Promise<{
    user: User;
    workspace: Workspace;
  }> {
    const apiKey = await this.db
      .selectFrom('apiKeys')
      .selectAll()
      .where('id', '=', payload.apiKeyId)
      .executeTakeFirst();

    if (!apiKey || apiKey.deletedAt !== null) {
      throw new UnauthorizedException('API key not found');
    }

    if (apiKey.expiresAt && apiKey.expiresAt < new Date()) {
      throw new UnauthorizedException('API key expired');
    }

    const workspace = await this.workspaceRepo.findById(payload.workspaceId);
    if (!workspace) {
      throw new UnauthorizedException();
    }

    const user = await this.userRepo.findById(payload.sub, payload.workspaceId);
    if (!user || isUserDisabled(user)) {
      throw new UnauthorizedException();
    }

    // Fire-and-forget: never block or fail auth on last-used bookkeeping.
    this.db
      .updateTable('apiKeys')
      .set({ lastUsedAt: new Date() })
      .where('id', '=', apiKey.id)
      .execute()
      .catch((err) => this.logger.warn(`Failed to update lastUsedAt: ${err}`));

    return { user, workspace };
  }
}
