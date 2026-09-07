import { IsBoolean, IsOptional } from 'class-validator';

export class PutV1ShareDto {
  /** true = create-or-update the share; false = delete it. */
  @IsBoolean()
  shared: boolean;

  @IsOptional()
  @IsBoolean()
  includeSubPages?: boolean;

  @IsOptional()
  @IsBoolean()
  searchIndexing?: boolean;
}
