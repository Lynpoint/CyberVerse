"""Loopback-only fallback when Docker Desktop does not publish new ports."""
import asyncio
import json
import subprocess


CONTAINER = 'shiyi-avatar-assist-inference-1'
CHILD = '''import os,select,socket,sys
s=socket.create_connection(('api',int(sys.argv[1])),timeout=10)
s.settimeout(None)
inputs=[s,0]
while inputs:
 for source in select.select(inputs,[],[])[0]:
  if source==0:
   data=os.read(0,65536)
   if data:s.sendall(data)
   else:
    inputs.remove(0)
    s.shutdown(socket.SHUT_WR)
  else:
   data=s.recv(65536)
   if not data:
    s.close()
    sys.exit(0)
   sys.stdout.buffer.write(data)
   sys.stdout.buffer.flush()
'''


async def relay(reader, writer, port):
    process = None
    tasks = []
    try:
        process = await asyncio.create_subprocess_exec(
            'docker', 'exec', '-i', CONTAINER, 'python3', '-u', '-c', CHILD, str(port),
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )

        async def upload():
            while data := await reader.read(65536):
                process.stdin.write(data)
                await process.stdin.drain()
            process.stdin.close()

        async def download():
            while data := await process.stdout.read(65536):
                writer.write(data)
                await writer.drain()

        tasks = [asyncio.create_task(upload()), asyncio.create_task(download())]
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    except (OSError, ConnectionError, asyncio.CancelledError):
        pass
    finally:
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        writer.close()
        if process is not None:
            if process.returncode is None:
                process.terminate()
            await process.wait()


async def main():
    info = json.loads(subprocess.check_output(['docker', 'inspect', CONTAINER], text=True))[0]
    if info['Config'].get('Labels', {}).get('com.docker.compose.project') != 'shiyi-avatar-assist':
        raise SystemExit('Unexpected container owner')
    servers = []
    for port in [18082, 18445]:
        server = await asyncio.start_server(
            lambda reader, writer, p=port: relay(reader, writer, p), '127.0.0.1', port,
        )
        servers.append(server)
    print('SHIYI_AVATAR_LOOPBACK_READY 18082 18445', flush=True)
    await asyncio.gather(*(server.serve_forever() for server in servers))


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
