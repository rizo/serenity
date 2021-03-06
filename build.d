#!/usr/bin/env dmd -w -O -inline -run
/**
 * Serenity Web Framework
 *
 * build.d: Build applications based on Serenity
 *
 * Authors: Robert Clipsham <robert@octarineparrot.com>
 * Copyright: Copyright (c) 2011, Robert Clipsham <robert@octarineparrot.com> 
 * License: New BSD License, see COPYING
 */

import std.algorithm;
import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.process;
import std.parallelism;
import std.range;
import std.stdio;
import std.string;

enum serenity = [
                    "serenity/backend/Backend.d",
                    "serenity/backend/FastCGI.d",
                    "serenity/bindings/FastCGI.d",
                    "serenity/bindings/Sqlite.d",
                    "serenity/core/Controller.d",
                    "serenity/core/Dispatcher.d",
                    "serenity/core/Form.d",
                    "serenity/core/Layout.d",
                    "serenity/core/Log.d",
                    "serenity/core/Request.d",
                    "serenity/core/Response.d",
                    "serenity/core/Router.d",
                    "serenity/core/Serenity.d",
                    "serenity/core/Util.d",
                    "serenity/document/Document.d",
                    "serenity/document/Html5Printer.d",
                    "serenity/document/HtmlDocument.d",
                    "serenity/document/HtmlPrinter.d",
                    "serenity/persister/backend/Sqlite.d",
                    "serenity/persister/Persister.d",
                    "serenity/persister/Query.d",
                    "serenity/persister/Sqlite.d",
                    "serenity/SqlitePrinter.d"
                ];

enum backends = [
                    "FastCGI" : "-L-lfcgi -version=EnableFastCGIBackend "
                ];

enum persisters = [
                    "SQLite" : "-L-lsqlite3 -version=EnableSqlitePersister "
                  ];

shared string buildOpts;
shared string[] packages;
shared bool verbose;

string green(string str) @property
{
    version (Posix)
    {
        return "\033[1;32m" ~ str ~ "\033[0;38m";
    }
    else
    {
        return str;
    }
}

string red(string str) @property
{
    version (Posix)
    {
        return "\033[1;31m" ~ str ~ "\033[0;38m";
    }
    else
    {
        return str;
    }
}

string yellow(string str) @property
{
    version (Posix)
    {
        return "\033[1;33m" ~ str ~ "\033[0;38m";
    }
    else
    {
        return str;
    }
}

void benforce(string file = __FILE__, size_t line = __LINE__)(bool value, string msg)
{
    if (!value)
    {
        throw new BuildFail(msg, file, line);
    }
}

class BuildFail : Exception
{
    this(string msg, string file, size_t line)
    {
        super(msg, file, line);
    }
}

void buildSerenity()
{
    writeln("> Building lib/libserenity.a".green);
    string build = "/usr/bin/env dmd -oflib/libserenity.a -lib ";
    foreach (file; serenity)
    {
        build ~= file ~ ' ';
    }
    build ~= buildOpts;
    verbose && writefln(yellow("> " ~ build));
    benforce(system(build) == 0, "lib/libserenity.a");
    benforce("lib/libserenity.a".exists, "lib/libserenity.a");
}

void buildPackage(string p)
{
    writefln("> Building package lib/libserenity-%s.a".green, p);
    string build = "/usr/bin/env dmd -oflib/libserenity-" ~ p ~ ".a -lib ";
    foreach (file; filter!q{endsWith(a.name, ".d")}(dirEntries(p, SpanMode.depth)))
    {
        build ~= file.name ~ ' ';
    }
    build ~= buildOpts;
    verbose && writefln(yellow("> " ~ build));
    benforce(system(build) == 0, "lib/libserenity-" ~ p ~ ".a");
    benforce(exists("lib/libserenity-" ~ p ~ ".a"), "lib/libserenity-" ~ p ~ ".a");
}

void genControllers()
{
    writeln("> Generating controllers.d".green);
    auto file = File("controllers.d", "w");
    file.writeln(`// Automatically generated, do not edit by hand`);
    file.writeln(`module controllers;`);
    foreach (p; packages)
    {
        foreach (f; filter!q{endsWith(a.name, ".d")}(dirEntries(p ~ "/controllers/", SpanMode.shallow)))
        {
            file.writefln("import %s.controllers.%s;", p, basename(f.name, ".d"));
        }
    }
}

void genLayouts()
{
    writeln("> Generating layouts.d".green);
    auto file = File("layouts.d", "w");
    file.writeln(`// Automatically generated, do not edit by hand`);
    file.writeln(`module layouts;`);
    foreach (p; packages)
    {
        foreach (f; filter!q{endsWith(a.name, ".d")}(dirEntries(p ~ "/layouts/", SpanMode.shallow)))
        {
            file.writefln("import %s.layouts.%s;", p, basename(f.name, ".d"));
        }
    }
}

void buildBinary()
{
    enforce(packages.length, "Cannot build a binary with no packages");
    genControllers();
    genLayouts();
    writeln("> Building binary bin/serenity.fcgi".green);
    string build = "/usr/bin/env dmd -ofbin/serenity.fcgi bootstrap.d controllers.d layouts.d -L-Llib ";
    foreach (p; packages)
    {
        build ~= "-L-lserenity-" ~ p ~ " ";
    }
    // This has to go after to prevent linker errors
    build ~= "-L-lserenity ";
    build ~= buildOpts;
    verbose && writefln(yellow("> " ~ build));
    benforce(system(build) == 0, "bin/serenity.fcgi");
}

int main(string[] args)
{
    bool buildBin = true;
    bool clean, exit, release;
    string remote = null, remoteDir = null;
    getopt(args,
            "r|release", &release,
            "no-binary", { buildBin = false; },
            "enable-backend", (string, string backend)
                              {
                                    // TODO should probably be case insensitive
                                    enforce(backend in backends, "Invalid Backend");
                                    buildOpts ~= backends[backend];
                              },
            "enable-persister", (string, string persister)
                                {
                                    enforce(persister in persisters, "Invalid Persister");
                                    buildOpts ~= persisters[persister];
                                },
            "p|build-package", (string, string p)
                             {
                                 packages ~= p;
                             },
            "remote", &remote,
            "remote-dir", &remoteDir,
            "h|help", {
                        writeln("Serenity Web Framework Builder");
                        writeln("usage: ./build.d [options]");
                        writeln("");
                        writeln("Options:");
                        writeln("   --release                       build in release mode");
                        writeln("   --no-binary                     do not build a binary");
                        writeln("   --enable-backend=<backend>      enable backend <backend>");
                        writeln("   --enable-persister=<persister>  enable persister <persister>");
                        writeln("   --build-package=<package>       build package <package>");
                        writeln("   --remote=<user@host>            build serenity on a remote machine");
                        writeln("   --remote-dir=<directory>        specify the directory to install to");
                        writeln("   --help                          print this help message");
                        writeln("   --clean                         clean the build");
                        writeln("   --verbose                       print commands as they are run");
                        exit = true;
                    },
            "c|clean", { clean = true; },
            "v|verbose", { verbose = true; }
         );
    if (exit)
    {
        return 0;
    }

    chdir(dirname(__FILE__));

    if (remote)
    {
        if (!remoteDir)
        {
            stderr.writefln("> Must specify a directory to install to on the remote".red);
            return 1;
        }
        try
        {
            verbose && writefln(yellow("> ssh " ~ remote ~ " mktemp -d -t serenityBuildXXXXXXXX"));
            auto tmp = chomp(shell("ssh " ~ remote ~ " mktemp -d -t serenityBuildXXXXXXXX"));
            verbose && writefln(yellow("> scp -r . " ~ remote ~ ":" ~ tmp));
            benforce(system("scp -qCr . " ~ remote ~ ":" ~ tmp ) == 0, "Copying files to remote");
            // TODO Passthrough args
            verbose && writefln(yellow("> ssh " ~ remote ~ " /usr/bin/env dmd -w -O -release -inline -run " ~ tmp ~ "/build.d"));
            benforce(system("ssh " ~ remote ~ " /usr/bin/env dmd -w -O -release -inline -run " ~ tmp ~ "/build.d") == 0, "Building on remote");
            verbose && writefln(yellow("> ssh " ~ remote ~ " 'cp -r " ~ tmp ~ " " ~ remoteDir ~ "'"));
            benforce(system("ssh " ~ remote ~ " 'cp -r " ~ tmp ~ "/* " ~ remoteDir ~ "'") == 0, "Installation");
            verbose && writefln(yellow("> ssh " ~ remote ~ " 'rm -rf " ~ tmp ~ "'"));
            benforce(system("ssh " ~ remote ~ " 'rm -rf " ~ tmp ~ "'") == 0, "Removing temporary files");
            return 0;
        }
        catch (BuildFail e)
        {
            stderr.writefln(red("> " ~ e.msg ~ " failed"));
            stderr.writeln(">>> REMOTE BUILD FAILED <<<".red);
            return 1;
        }
        catch (Throwable e)
        {
            stderr.writefln(e.toString());
            stderr.writeln(">>> REMOTE BUILD FAILED <<<".red);
            return 1;
        }
    }

    if (clean)
    {
        scope(failure) stderr.writeln(">>> BUILD FAILED <<<".red);
        writeln("> Cleaning build".green);
        void removeLoopBody(string f)
        {
            if (f.exists)
            {
                verbose && writefln(yellow("> rm " ~ f));
                remove(f);
            }
        }
        // TODO Use Regex when std.file is updated to use it
        foreach (f; filter!q{endsWith(a.name, ".o")}(dirEntries(".", SpanMode.depth)))
        {
            removeLoopBody(f.name);
        }
        foreach (f; filter!q{endsWith(a.name, ".a")}(dirEntries(".", SpanMode.depth)))
        {
            removeLoopBody(f.name);
        }
        foreach (f; ["controllers.d", "layouts.d", "bin/serenity.fcgi"])
        {
            removeLoopBody(f);
        }
        return 0;
    }

    if (!buildOpts)
    {
        if (release)
        {
            buildOpts ~= "-wi -O -release -inline " ~ backends["FastCGI"] ~ persisters["SQLite"];
        }
        else
        {
            // TODO Should use -w too, disabled until new std.stream is in place
            buildOpts = "-d -wi -gc -debug -unittest " ~ backends["FastCGI"] ~ persisters["SQLite"];
        }
    }
    else if (release)
    {
        buildOpts = "-wi -O -release -inline " ~ buildOpts;
    }

    if (!packages)
    {
        packages ~= "example";
    }

    try
    {
        auto t = task!buildSerenity();
        taskPool.put(t);
        foreach (p; parallel(packages))
        {
            buildPackage(p);
        }
        t.yieldForce();
        if (buildBin)
        {
            buildBinary();
        }
    }
    catch (BuildFail e)
    {
        stderr.writefln(red("> Build of " ~ e.msg ~ " failed"));
        stderr.writeln(">>> BUILD FAILED <<<".red);
        return 1;
    }
    catch (Throwable e)
    {
        stderr.writefln(e.toString());
        stderr.writeln(">>> BUILD FAILED <<<".red);
        return 1;
    }
    return 0;
}
