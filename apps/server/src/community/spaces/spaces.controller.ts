import {
  Body,
  Controller,
  ForbiddenException,
  Get,
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
import { User, Workspace } from '@docmost/db/types/entity.types';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { SpaceMemberService } from '../../core/space/services/space-member.service';
import { SpaceService } from '../../core/space/services/space.service';
import { SpaceMemberRepo } from '@docmost/db/repos/space/space-member.repo';
import { findHighestUserSpaceRole } from '@docmost/db/repos/space/utils';
import SpaceAbilityFactory from '../../core/casl/abilities/space-ability.factory';
import {
  SpaceCaslAction,
  SpaceCaslSubject,
} from '../../core/casl/interfaces/space-ability.type';
import WorkspaceAbilityFactory from '../../core/casl/abilities/workspace-ability.factory';
import {
  WorkspaceCaslAction,
  WorkspaceCaslSubject,
} from '../../core/casl/interfaces/workspace-ability.type';
import { V1PaginationDto } from '../dto/v1-pagination.dto';
import { toDataEnvelope, toPaginationOptions } from '../pagination';
import { V1ExceptionFilter } from '../http/error-filter';
import { CreateV1SpaceDto, UpdateV1SpaceDto } from './dto/space.dto';

/**
 * v1 spaces. Same CASL gates as core's SPA controller (principle 9),
 * resource-shaped REST on top.
 */
@UseGuards(JwtAuthGuard)
@UseFilters(V1ExceptionFilter)
@Controller('v1/spaces')
export class SpacesController {
  constructor(
    private readonly spaceService: SpaceService,
    private readonly spaceMemberService: SpaceMemberService,
    private readonly spaceMemberRepo: SpaceMemberRepo,
    private readonly spaceAbility: SpaceAbilityFactory,
    private readonly workspaceAbility: WorkspaceAbilityFactory,
  ) {}

  @Get('/')
  async getSpaces(
    @Query() pagination: V1PaginationDto,
    @AuthUser() user: User,
  ) {
    const result = await this.spaceMemberService.getUserSpaces(
      user.id,
      toPaginationOptions(pagination.limit, pagination.cursor),
    );

    if (result.items.length > 0) {
      const spaceIds = result.items.map((s) => s.id);
      const roles = await this.spaceMemberRepo.getUserRolesForSpaces(
        user.id,
        spaceIds,
      );

      const roleMap = new Map<string, string[]>();
      for (const row of roles) {
        const existing = roleMap.get(row.spaceId) || [];
        existing.push(row.role);
        roleMap.set(row.spaceId, existing);
      }

      result.items = result.items.map((space) => {
        const spaceRoles = roleMap.get(space.id);
        const role = spaceRoles
          ? findHighestUserSpaceRole(
              spaceRoles.map((r) => ({ userId: user.id, role: r })),
            )
          : undefined;

        return { ...space, membership: { userId: user.id, role } };
      });
    }

    return toDataEnvelope(result);
  }

  @Get('/:spaceId')
  async getSpace(
    @Param('spaceId') spaceId: string,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const space = await this.spaceService.getSpaceInfo(spaceId, workspace.id);

    if (!space) {
      throw new NotFoundException('Space not found');
    }

    const ability = await this.spaceAbility.createForUser(user, space.id);
    if (ability.cannot(SpaceCaslAction.Read, SpaceCaslSubject.Settings)) {
      throw new ForbiddenException();
    }

    const userSpaceRoles = await this.spaceMemberRepo.getUserSpaceRoles(
      user.id,
      space.id,
    );

    return {
      ...space,
      membership: {
        userId: user.id,
        role: findHighestUserSpaceRole(userSpaceRoles),
        permissions: ability.rules,
      },
    };
  }

  @Post('/')
  createSpace(
    @Body() dto: CreateV1SpaceDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const ability = this.workspaceAbility.createForUser(user, workspace);
    if (ability.cannot(WorkspaceCaslAction.Manage, WorkspaceCaslSubject.Space)) {
      throw new ForbiddenException();
    }

    return this.spaceService.createSpace(user, workspace.id, dto);
  }

  @Patch('/:spaceId')
  async updateSpace(
    @Param('spaceId') spaceId: string,
    @Body() dto: UpdateV1SpaceDto,
    @AuthUser() user: User,
    @AuthWorkspace() workspace: Workspace,
  ) {
    const ability = await this.spaceAbility.createForUser(user, spaceId);
    if (ability.cannot(SpaceCaslAction.Manage, SpaceCaslSubject.Settings)) {
      throw new ForbiddenException();
    }

    return this.spaceService.updateSpace(
      {
        spaceId,
        name: dto.name,
        description: dto.description,
      } as any,
      workspace.id,
    );
  }
}
