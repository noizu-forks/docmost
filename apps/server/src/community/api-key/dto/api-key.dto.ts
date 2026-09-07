import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class CreateApiKeyDto {
  @IsString()
  @MinLength(1)
  @MaxLength(255)
  name: string;

  /**
   * JWT lifetime for the minted key, e.g. '10y'. When omitted a long
   * default is applied so keys never silently expire with the workspace's
   * regular token TTL.
   */
  @IsOptional()
  @IsString()
  @IsIn(['90d', '1y', '5y', '10y'])
  expiresIn?: string;
}

export class ApiKeyIdDto {
  @IsString()
  id: string;
}
