
import {
    APIGatewayProxyEventV2,
    APIGatewayProxyResultV2,
    Context,
} from "https://deno.land/x/lambda/mod.ts";


type HandlerFunction = (
  event: APIGatewayProxyEventV2,
  context: Context,
) => void;

function maybeJson(headers: Headers, headerName: string) {
  const raw = headers.get(headerName);
  let json = undefined;
  if (raw) {
    try {
      json = JSON.parse(raw);
    } catch (e) {
      // if the header is present AND is not valid JSON then something is broken(?)
      console.error(
        'Unable to parse header', headerName, 'value as JSON:', raw
      );
    }
  }
  return json
}

const mandatoryEnvVariable = (name: string): string => {
  const valueOrUndefined = Deno.env.get(name);
  if (! valueOrUndefined) {
    throw new Error(`Missing mandatory environment variable: ${name}`);
  }

  return valueOrUndefined
}

const mandatoryHeader = (headers: Headers, name: string): string => {
  const valueOrUndefined = headers.get(name);
  if (! valueOrUndefined) {
    throw new Error(`Missing mandatory header: ${name}`);
  }
  return valueOrUndefined
}

export const lambdaEntryPoint = async (handlerFunction: HandlerFunction) => {
  console.info("=====[ENTRY INTO BOOTSTRAP]=====")

  const workingDir = mandatoryEnvVariable("LAMBDA_TASK_ROOT")
  Deno.chdir(workingDir)
  console.debug(`Working directory is now ${workingDir} -- files present:`)
  for await (const dirEntry of Deno.readDir(".")) {
    console.debug(dirEntry.name)
  }

  const API_ROOT=`http://${mandatoryEnvVariable("AWS_LAMBDA_RUNTIME_API")}/2018-06-01/runtime/`
  const INVOCATION = `${API_ROOT}invocation/`;
  const next = await fetch(INVOCATION + 'next');
  const headers = next.headers;
  const requestId = mandatoryHeader(headers, 'lambda-runtime-aws-request-id');
  Deno.env.set('_X_AMZN_TRACE_ID', mandatoryHeader(headers, 'lambda-runtime-trace-id'));
  const context: Context = {
    functionName: mandatoryEnvVariable("AWS_LAMBDA_FUNCTION_NAME"),
    functionVersion: mandatoryEnvVariable("AWS_LAMBDA_FUNCTION_VERSION"),
    invokedFunctionArn: mandatoryHeader(headers, 'lambda-runtime-invoked-function-arn'),
    memoryLimitInMB: mandatoryEnvVariable("AWS_LAMBDA_FUNCTION_MEMORY_SIZE"),
    awsRequestId: requestId,
    logGroupName: mandatoryEnvVariable("AWS_LAMBDA_LOG_GROUP_NAME"),
    logStreamName: mandatoryEnvVariable("AWS_LAMBDA_LOG_STREAM_NAME"),
    identity: maybeJson(headers, 'lambda-runtime-cognito-identity'),
    clientContext: maybeJson(headers, 'lambda-runtime-client-context'),
    getRemainingTimeInMillis: () =>  {
      return Number(mandatoryHeader(headers, 'lambda-runtime-deadline-ms')) - Date.now();
    },
    // NOTE: we add these for type compatibility with Definitely Typed.
    callbackWaitsForEmptyEventLoop: false,
    done: (error: Error) => {},
    fail: (error: Error) => {},
    succeed: (messageOrObject: any) => {}
  }
  let res;
  try {
    const event = await next.json();

    // passed-in callback
    const body = await handlerFunction(event, context);

    res = await fetch(INVOCATION + requestId + '/response', {
      method: 'POST',
      body: JSON.stringify(body)
    });
  } catch(e) {
    console.error(e);
    // If it's an Error we can pull these out cleanly...
    // BUT it's javascript so it could be anything!
    // If there's a better way, very happy to take suggestions.
    let name, message;
    try {
      name = e.name || 'Error'
    } catch (_) {
      name = 'Error'
    }
    try {
      message = e.message || e
    } catch (_) {
      message = e
    }
    if (typeof(name) !== 'string') {
      name = JSON.stringify(name)
    }
    if (typeof(message) !== 'string') {
      const s = JSON.stringify(message)
      message = s === undefined ? '' + message : s
    }
    res = await fetch(INVOCATION + requestId + '/error', {
      method: 'POST',
      body: JSON.stringify({
        errorMessage: message,
        errorType: name
      })
    });
  }
  await res.blob();
}
