const waitReady = (timeoutMs: number): Promise<boolean> =>
  new Promise(resolve => {
    const deadline = Date.now() + timeoutMs;

    function check(): void {
      if (document.readyState === "complete") {
        resolve(true);
      } else if (Date.now() >= deadline) {
        resolve(false);
      } else {
          setTimeout(check, 25);
        }
    }

    check();
  });
