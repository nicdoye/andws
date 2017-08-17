# andws

Another Dumb Web Server

## Really Dumb

This isn't the sort of thing I would ever expect anyone to use, but it demonstrates what can be done in some simple Perl. It's not rigorous (you could easily confuse it) or RFC compliant in any way.

## What is it?

It's another simple "run in place" web server.

## Usage

```bash
> cd "${directory_i_want_to_serve}"
> andws
```

Browse the files in that folder at  
http://localhost:1444

Press `^C` and then download a better server, such as [Caddy](https://caddyserver.com/).

## So many broken things

Future improvements would involve refactoring to have more classes, e.g. for response and headers. Inline HTML looks like code from the late 90s.

Obviously a good feature would be to deliver files with the correct mime-type so they can be renderred in a browser.

It contains the obvious security flaw that it doesn't use [`realpath(3)`](http://man7.org/linux/man-pages/man3/realpath.3.html), [`canonicalize_file_name(3)`](http://man7.org/linux/man-pages/man3/canonicalize_file_name.3.html), [`System.IO.GetFullPathName`](https://msdn.microsoft.com/en-us/library/system.io.path.getfullpath(v=vs.110).aspx), or whatever.

It only runs on UNIX, but doesn't support certain non-POSIX file types (e.g [Solaris doors](https://docs.oracle.com/cd/E36784_01/html/E36861/gmhhn.html) should be displayed as `D`).

It probably doesn't allow for concurrent sessions.

sticky-bits not displayed.

`Content-Length` and `Transfer-Encoding: chunked` are missing.

There is a remarkable lack of unit tests. Or any tests.

_(Pull requests welcome.)_

### Author, Copyright

Copyright &#x24B8; 2017 [Nicolas Doye](https://worldofnic.org)

### License

[Apache License, Version 2.0](https://opensource.org/licenses/Apache-2.0)
