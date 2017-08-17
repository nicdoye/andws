# andws

Another Dumb Web Server 0.005

## Really Dumb

This isn't the sort of thing I would ever expect anyone to use, but it demonstrates what can be done in some simple Perl. It's not rigorous (you could easily confuse it) or RFC compliant in any way.

## What is it?

It's another simple "run in place" web server.

## Usage

### Basic usage from your shell

```bash
> cd "${directory_i_want_to_serve}"
> andws
```

Browse the files in that folder at  
http://localhost:1444

Press `^C` and then download a better server, such as [Caddy](https://caddyserver.com/).

### From within perl, itself

You can also override some of the defaults from within perl:

```perl
use And::WebServer;

my $server = And::WebServer->new({ port => 23412, document_root => '/tmp' });
```

## So many broken things

* Refactoring to have more classes, e.g. for files, response and headers.
* Inline HTML looks like code from the late 90s. It's not even valid HTML.
* It uses Internal Server Error when it should not. (e.g. permissions).
* It contains the obvious security flaw that it doesn't use [`realpath(3)`](http://man7.org/linux/man-pages/man3/realpath.3.html), [`canonicalize_file_name(3)`](http://man7.org/linux/man-pages/man3/canonicalize_file_name.3.html), [`System.IO.GetFullPathName`](https://msdn.microsoft.com/en-us/library/system.io.path.getfullpath(v=vs.110).aspx), or whatever. However, by accident (rather than design) it seems to do the right thing, but it _should_ do proper checking.
* It follows symlinks and there's no option to turn it off. That's another well-known security issue.
* It only runs on UNIX.
* It doesn't support certain non-standard file types (e.g [Solaris doors](https://docs.oracle.com/cd/E36784_01/html/E36861/gmhhn.html) should be displayed as `D`).
* It probably doesn't allow for concurrent sessions.
* sticky-bits not displayed.
* `Content-Length` and `Transfer-Encoding: chunked` are missing.
* There is a remarkable lack of unit tests.
* Or any tests.
* Error checking is distinctly lacking.
* It's fragile: as it doesn't recover from certain errors: it just dies (and that's not from me calling [`die()`](https://perldoc.perl.org/functions/die.html), either - I don't call it).

_(Pull requests welcome.)_

### Author, Copyright

Copyright &#x24B8; 2017 [Nicolas Doye](https://worldofnic.org)

### License

[Apache License, Version 2.0](https://opensource.org/licenses/Apache-2.0)
