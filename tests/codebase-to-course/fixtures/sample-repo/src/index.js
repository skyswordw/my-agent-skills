import { routeAction } from "./router.js";
import { incrementCount } from "./store.js";

export function wireCounter(button) {
  button.addEventListener("click", () => {
    routeAction("increment", incrementCount);
  });
}
