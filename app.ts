import {
    APIGatewayProxyEventV2,
    APIGatewayProxyResultV2,
    Context,
} from "https://deno.land/x/lambda/mod.ts";
import { lambdaEntryPoint } from "./lambda.ts";


// your handler function...
const handler = async (
    event: APIGatewayProxyEventV2,
    context: Context,
): Promise<APIGatewayProxyResultV2> =>  {
  console.log("entered handle()")
  const someJsonText = JSON.stringify({
      message: "Hello, World!",
  });
  return {
    body: someJsonText,
    headers: { "content-type": "application/json" },
    statusCode: 200,
  };
}


// copy paste from here =====
const main = async () => {
  await lambdaEntryPoint(handler)
}

await main();
// ===== to here
