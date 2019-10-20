# miniphab

A completely containerized Phabricator. All persistent data — files, databases,
and repositories — is stored in `/var/lib/phabricator`, making it a good Docker
volume candidate.

Meant for testing purposes only. Use at your own risk.

## Usage

1. Start the container.

```bash
docker run \
    -d \
    -p 80:80 \
    -e PORT=80 \
    -p 2222:22 \
    -e SSH_PORT=2222 \
    -v miniphab:/var/lib/phabricator \
    awkspace/miniphab
```

2. Navigate to http://phabricator.localhost/.
3. Register an admin account.
4. Configure an [authentication provider][auth].
5. (Optional) Rerun the container with `-e LOCK_AUTH=1` to prevent further
   changes to authentication.

## Build variables

| Name       | Default | Description                                     |
|:-----------|:--------|:------------------------------------------------|
| `VCS_USER` | `git`   | The user account for working with VCS over SSH. |

## Environment variables

| Name         | Default                 | Description                                                                                 |
|:-------------|:------------------------|:--------------------------------------------------------------------------------------------|
| `PROTO`      | `http`                  | The user-facing protocol (http or https).                                                   |
| `DOMAIN`     | `phabricator.localhost` | The domain to use. Phabricator [insists it have a dot][dot].                                |
| `CDN_DOMAIN` | `usercontent.localhost` | A separate domain for uploaded content. Phabricator [insists on making this separate][cdn]. |
| `PORT`       | `80`                    | The exposed port that Phabricator runs on.                                                  |
| `SSH_PORT`   | `22`                    | The exposed port that Diffusion’s SSH server runs on.                                       |
| `LOCK_AUTH`  | `0`                     | Once [auth is configured][auth], set to `1` to prevent changes.                             |
| `TZ`         | `Etc/UTC`               | Set to the [PHP timezone][tz] of your choice.                                               |

## Meet the daemons

Phabricator requires a lot of things running to operate correctly. Some could
probably be separated out via `docker-compose` (`mysqld`, `nginx`) while others
need to be running on the same host (`sshd`) for all of Phabricator’s features
to work.

`miniphab` takes the simpler approach by jamming everything into a single image,
glued together by [s6][s6-o].

### mysqld

A MariaDB installation. Writes to `/var/lib/phabricator/db` and is available
without authentication at `/run/mysqld/mysqld.sock`. Signals readiness to s6
once the MariaDB client is able to successfully connect. Runs as `mysql`.

### postfix

Phabricator is opinionated in many ways, and one of those ways is that [admins
can’t directly set account passwords][passwords]. So, unfortunately, if you set
yourself up with basic username/password authentication, the only way to set
your password for the first time is email. Running a mail daemon is the simplest
way out of this predicament.

Runs as `postfix`.

### logpipe

A workaround for a ridiculous [Docker issue][moby-6880] that prevents
unprivileged services from logging to `/dev/stderr`. It’s also the only script
not written in pure [`execline`][execline] because I couldn’t wrap my head
around chaining `redirfd` here.

`logpipe` creates a named pipe at `/run/logpipe` that allows unprivileged
services to log to standard error if they insist on logging to something that
looks like a file.

Runs as `root` because only `root` is powerful enough to log to standard streams
in the Dockerverse, apparently.

### aphlict

The [Phabricator notification system][aphlict], which runs separately from
Phabricator itself, presumably because WebSockets are a helluva lot easier in
Node. Is necessary for [Conpherence][conpherence] to like... work. At all. Runs
as `nobody`.

### setup

Not really a daemon per se, but an `execline` script configured to act as much
like a `systemd` oneshot as possible.

This script runs a bunch of stuff that has to wait for `mysqld` to be available,
but should get run before Phabricator starts in earnest. It runs the database
migrations, ensures the persistent data directories in `/var/lib/phabricator`
exist with the right permissions, and translates some of the container’s
environment variables into “runtime” configurations for Phabricator.

It also starts `phd`, the Phabricator daemon manager, but not in a supervised
manner. Turns out that `phd` [does not want to be supervised][phd-fork], which
is of course a [perfectly valid point of view][nms], but it means that s6 has
exactly zero awareness of `phd` and can’t resurrect it if it dies.

It’s possible to run each daemon in debug mode, but Phabricator seems to have no
interest in providing a stable interface with its daemons outside of `phd
start`, so the only viable option is to put our blind trust in a PHP daemon
runner.

The `phd` daemons run as their own user, `phd`. For [Diffusion][diffusion] to
function properly, the VCS user (default `git`) and `nobody` have limited `sudo`
capabilities to run VCS-related commands as `phd` because that’s seriously how
Diffusion works.

### php-fpm

The classic PHP FastCGI manager. Waits for `/run/logpipe` because it wants to
log to a file. Runs as `nobody`.

### sshd

Used for SSH access to [Diffusion repositories][diffusion] because, let’s be
honest, SSH is the only way anyone wants to interact with git.

Generates host keys in `/var/lib/phabricator/ssh` to avoid having to modify
`known_hosts` every time you rebuild the image. Runs as `root`.

### nginx

Defaults to down and is started by the `setup` “oneshot” to avoid Phabricator
doing anything crafty before the database is ready. Also logs to `/run/logpipe`.
Runs as `nginx`.

`nginx` is configured pretty much per [Phabricator’s documentation][nginx] and
includes [websocket forwarding][nginx-ws] to avoid having to expose another
port.

[aphlict]: https://secure.phabricator.com/book/phabricator/article/notifications/
[auth]: https://secure.phabricator.com/book/phabricator/article/configuring_accounts_and_registration/
[cdn]: https://secure.phabricator.com/book/phabricator/article/configuring_file_domain/
[conpherence]: https://www.phacility.com/phabricator/conpherence/
[diffusion]: https://secure.phabricator.com/book/phabricator/article/diffusion_hosting/
[dot]: https://secure.phabricator.com/book/phabricator/article/configuration_guide/#webserver-configuring-apache
[execline]: https://skarnet.org/software/execline/
[moby-6880]: https://github.com/moby/moby/issues/6880
[nginx-ws]: https://secure.phabricator.com/book/phabricator/article/notifications/#terminating-ssl-with-nginx
[nginx]: https://secure.phabricator.com/book/phabricator/article/configuration_guide/#webserver-configuring-nginx
[nms]: https://www.youtube.com/watch?v=YEwlW5sHQ4Q
[passwords]: https://secure.phabricator.com/D18901?id=45357
[phd-fork]: https://secure.phabricator.com/T10786
[s6-o]: https://github.com/just-containers/s6-overlay
[tz]: https://www.php.net/manual/en/timezones.php
