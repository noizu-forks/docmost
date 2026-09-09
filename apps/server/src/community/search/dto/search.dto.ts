import { Type } from 'class-transformer';
import { IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

/**
 * GET /v1/search?q= — `q` maps onto core SearchDTO.query. limit is capped
 * like core's default of 25; cursor is an opaque offset token (core search
 * is rank/limit/offset only — see SearchController).
 */
export class V1SearchDto {
  @IsOptional()
  @IsString()
  q?: string;

  @IsOptional()
  @IsString()
  spaceId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  @Max(100)
  limit?: number;

  @IsOptional()
  @IsString()
  cursor?: string;
}
