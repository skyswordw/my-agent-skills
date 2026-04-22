export function routeAction(action, handler) {
  if (action !== "increment") {
    throw new Error(`Unknown action: ${action}`);
  }

  return handler();
}
