import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
} from '@nestjs/common';
import { FastifyReply } from 'fastify';

const STATUS_TO_CODE: Record<number, string> = {
  400: 'bad_request',
  401: 'not_authorized',
  403: 'forbidden',
  404: 'not_found',
  409: 'conflict',
  422: 'validation_failed',
  429: 'rate_limited',
};

/**
 * Principle 3: uniform v1 error envelope
 * { error: { code, message, statusCode, details? } } with stable machine codes.
 * Handlers may pass a specific code via
 * `new HttpException({ code: 'page_not_found', message }, 404)`.
 */
@Catch()
export class V1ExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const response = host.switchToHttp().getResponse<FastifyReply>();

    let status = 500;
    let code = 'internal_error';
    let message = 'Internal server error';
    let details: unknown;

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const resp = exception.getResponse();
      if (typeof resp === 'string') {
        message = resp;
      } else if (resp && typeof resp === 'object') {
        message =
          typeof (resp as any).message === 'string'
            ? (resp as any).message
            : Array.isArray((resp as any).message)
              ? (resp as any).message.join(', ')
              : exception.message;
        if (typeof (resp as any).code === 'string') {
          code = (resp as any).code;
        }
        if (Array.isArray((resp as any).message)) {
          details = (resp as any).message;
        }
      }
      code = code !== 'internal_error' ? code : STATUS_TO_CODE[status] ?? 'error';
    }

    response.status(status).send({
      error: {
        code,
        message,
        statusCode: status,
        ...(details !== undefined ? { details } : {}),
      },
    });
  }
}
