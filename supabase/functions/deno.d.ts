// Deno and Supabase Edge Functions ambient type declarations for IDE/TypeScript language server

declare module "https://deno.land/std@0.168.0/http/server.ts" {
  export function serve(
    handler: (req: Request) => Response | Promise<Response>,
    options?: {
      port?: number;
      hostname?: string;
      signal?: AbortSignal;
      onError?: (error: unknown) => Response | Promise<Response>;
      onListen?: (params: { port: number; hostname: string }) => void;
    }
  ): void;
}

declare module "https://deno.land/std@*/http/server.ts" {
  export function serve(
    handler: (req: Request) => Response | Promise<Response>,
    options?: {
      port?: number;
      hostname?: string;
      signal?: AbortSignal;
      onError?: (error: unknown) => Response | Promise<Response>;
      onListen?: (params: { port: number; hostname: string }) => void;
    }
  ): void;
}

declare module "https://esm.sh/*" {
  const content: any;
  export default content;
}

declare namespace Deno {
  export interface Env {
    get(key: string): string | undefined;
    set(key: string, value: string): void;
    has(key: string): boolean;
    delete(key: string): void;
    toObject(): Record<string, string>;
  }

  export const env: Env;
  export const args: string[];
  export const version: {
    deno: string;
    v8: string;
    typescript: string;
  };
}
