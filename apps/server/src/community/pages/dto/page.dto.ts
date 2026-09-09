import { Type } from 'class-transformer';
import {
  IsIn,
  IsOptional,
  IsString,
  IsUUID,
  ValidateIf,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { ContentFormat } from '../../../core/page/dto/create-page.dto';

/** GET /v1/spaces/:spaceId/pages?parentId= */
export class ListSpacePagesDto {
  @IsOptional()
  @IsUUID()
  parentId?: string;
}

/** POST /v1/spaces/:spaceId/pages */
export class CreateV1PageDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  content?: string | object;

  @IsOptional()
  @IsUUID()
  parentId?: string;

  @IsOptional()
  @ValidateIf((o) => o.content !== undefined)
  @Transform(({ value }) => value?.toLowerCase() ?? 'markdown')
  @IsIn(['json', 'markdown', 'html'])
  format?: ContentFormat;
}

/** PATCH /v1/pages/:pageId */
export class PatchV1PageDto {
  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsUUID()
  parentId?: string;
}

/** PUT /v1/pages/:pageId/content */
export class PutV1PageContentDto {
  @IsString()
  content: string | object;

  @IsOptional()
  @Transform(({ value }) => value?.toLowerCase())
  @IsIn(['append', 'prepend', 'replace'])
  operation?: 'append' | 'prepend' | 'replace';

  @IsOptional()
  @Transform(({ value }) => value?.toLowerCase() ?? 'markdown')
  @IsIn(['json', 'markdown', 'html'])
  format?: ContentFormat;
}

/** GET /v1/pages/:pageId?format=&include= */
export class GetV1PageDto {
  @IsOptional()
  @IsString()
  format?: ContentFormat;

  @IsOptional()
  @IsString()
  include?: string;
}

export class DeleteV1PageDto {
  @IsOptional()
  @IsString()
  permanent?: string;
}

/** @Type conversion for GET query scalars (query params arrive as strings). */
export class V1PageQueryDto extends GetV1PageDto {
  @IsOptional()
  @Type(() => Number)
  limit?: number;
}
