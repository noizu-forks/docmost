import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayNotEmpty,
  ArrayUnique,
  IsBoolean,
  IsIn,
  IsUUID,
  ValidateNested,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { PagePermissionRole } from '../../../common/helpers/types/permission';

const ROLE_VALUES = [PagePermissionRole.READER, PagePermissionRole.WRITER];
export type V1GrantRole = PagePermissionRole;

export class V1GrantInputDto {
  @IsIn(['user', 'group'])
  type: 'user' | 'group';

  @IsUUID()
  principalId: string;

  @Transform(({ value }) => value?.toLowerCase())
  @IsIn(ROLE_VALUES)
  role: V1GrantRole;
}

/** POST /v1/pages/:pageId/access/grants — batch ≤25. */
export class PostV1GrantsDto {
  @ArrayNotEmpty()
  @ArrayUnique()
  @ArrayMaxSize(25)
  @ValidateNested({ each: true })
  @Type(() => V1GrantInputDto)
  grants: V1GrantInputDto[];
}

/** PUT /v1/pages/:pageId/access/restriction */
export class PutV1RestrictionDto {
  @IsBoolean()
  restricted: boolean;
}

/** PATCH /v1/pages/:pageId/access/grants/:grantId */
export class PatchV1GrantDto {
  @Transform(({ value }) => value?.toLowerCase())
  @IsIn(ROLE_VALUES)
  role: V1GrantRole;
}
