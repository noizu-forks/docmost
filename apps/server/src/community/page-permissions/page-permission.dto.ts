import {
  ArrayNotEmpty,
  ArrayUnique,
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
} from 'class-validator';
import { PaginationOptions } from '@docmost/db/pagination/pagination-options';
import { PagePermissionRole } from '../../common/helpers/types/permission';

export class PageIdDto {
  @IsUUID()
  pageId: string;
}

export class GetPagePermissionInfoDto extends PageIdDto {}

export class GetPagePermissionsDto extends PaginationOptions {
  @IsUUID()
  pageId: string;

  /** Batch filter form: only list permissions for these users. */
  @IsOptional()
  @ArrayNotEmpty()
  @ArrayUnique()
  @IsUUID('all', { each: true })
  userIds?: string[];

  /** Batch filter form: only list permissions for these groups. */
  @IsOptional()
  @ArrayNotEmpty()
  @ArrayUnique()
  @IsUUID('all', { each: true })
  groupIds?: string[];
}

export class RestrictPageDto extends PageIdDto {}

export class RemovePageRestrictionDto extends PageIdDto {}

export class AddPagePermissionDto extends PageIdDto {
  @IsString()
  @IsIn([PagePermissionRole.READER, PagePermissionRole.WRITER])
  role: PagePermissionRole;

  @IsOptional()
  @ArrayNotEmpty()
  @ArrayUnique()
  @IsUUID('all', { each: true })
  userIds?: string[];

  @IsOptional()
  @ArrayNotEmpty()
  @ArrayUnique()
  @IsUUID('all', { each: true })
  groupIds?: string[];
}

export class UpdatePagePermissionDto extends PageIdDto {
  @IsString()
  @IsIn([PagePermissionRole.READER, PagePermissionRole.WRITER])
  role: PagePermissionRole;

  @IsOptional()
  @IsUUID()
  userId?: string;

  @IsOptional()
  @IsUUID()
  groupId?: string;
}

export class RemovePagePermissionDto extends PageIdDto {
  @IsOptional()
  @ArrayNotEmpty()
  @ArrayUnique()
  @IsUUID('all', { each: true })
  userIds?: string[];

  @IsOptional()
  @ArrayNotEmpty()
  @ArrayUnique()
  @IsUUID('all', { each: true })
  groupIds?: string[];
}

// Re-exported for controllers building permission responses.
export { PagePermissionRole };
export type PagePermissionRoleValue = `${PagePermissionRole}`;
export interface PagePermissionEntry {
  type: 'user' | 'group';
  id: string;
  role: PagePermissionRoleValue;
}
