import { Type } from 'class-transformer';
import { IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

/** v1 pagination query params: ?limit=&cursor= (principle 2). */
export class V1PaginationDto {
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

/** Query params accepted but intentionally ignored are whitelisted away by the global ValidationPipe — unknown params never 400. */
export class V1PaginationWithSpaceDto extends V1PaginationDto {
  @IsOptional()
  @IsString()
  spaceId?: string;
}
