import { ArgumentsHost, BadRequestException, HttpException } from '@nestjs/common';
import { V1ExceptionFilter } from './error-filter';

describe('V1ExceptionFilter', () => {
  let reply: { status: jest.Mock; send: jest.Mock };
  let filter: V1ExceptionFilter;

  function host(): ArgumentsHost {
    return {
      switchToHttp: () => ({ getResponse: () => reply }),
    } as unknown as ArgumentsHost;
  }

  function sentBody() {
    return reply.send.mock.calls[0][0];
  }

  beforeEach(() => {
    reply = {
      status: jest.fn().mockReturnThis(),
      send: jest.fn(),
    };
    filter = new V1ExceptionFilter();
  });

  it('maps unknown exceptions to the internal_error fallback', () => {
    filter.catch(new Error('boom'), host());

    expect(reply.status).toHaveBeenCalledWith(500);
    expect(sentBody()).toEqual({
      error: {
        code: 'internal_error',
        message: 'Internal server error',
        statusCode: 500,
      },
    });
  });

  it('uses the status-to-code table for a string HttpException message', () => {
    filter.catch(new HttpException('nope', 400), host());

    expect(reply.status).toHaveBeenCalledWith(400);
    expect(sentBody()).toEqual({
      error: {
        code: 'bad_request',
        message: 'nope',
        statusCode: 400,
      },
    });
  });

  it('keeps the full body when the exception response is a plain object', () => {
    filter.catch(
      new HttpException({ code: 'not_authorized', message: 'bad key' }, 401),
      host(),
    );

    expect(reply.status).toHaveBeenCalledWith(401);
    expect(sentBody()).toEqual({
      error: {
        code: 'not_authorized',
        message: 'bad key',
        statusCode: 401,
      },
    });
  });

  it('joins a validation message array and exposes it as details', () => {
    const exception = new BadRequestException(['name must be a string', 'slug too short']);
    filter.catch(exception, host());

    expect(reply.status).toHaveBeenCalledWith(400);
    expect(sentBody()).toEqual({
      error: {
        code: 'bad_request',
        message: 'name must be a string, slug too short',
        statusCode: 400,
        details: ['name must be a string', 'slug too short'],
      },
    });
  });

  it('falls back to the exception message when the response object has no message', () => {
    filter.catch(new HttpException({ foo: 'bar' }, 409), host());

    expect(reply.status).toHaveBeenCalledWith(409);
    expect(sentBody().error.code).toBe('conflict');
    expect(sentBody().error.message).toBe(new HttpException({}, 409).message);
    expect(sentBody().error.details).toBeUndefined();
  });

  it('maps an unmapped status code to the generic error code', () => {
    filter.catch(new HttpException('tea time', 418), host());

    expect(sentBody().error.code).toBe('error');
    expect(sentBody().error.message).toBe('tea time');
  });

  it('ignores a non-string code from the response body', () => {
    filter.catch(new HttpException({ code: 42, message: 'gone' }, 404), host());

    expect(sentBody().error.code).toBe('not_found');
    expect(sentBody().error.message).toBe('gone');
  });
});
