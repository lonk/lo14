## How to use

### Start/Stop server

* To start a server :
<pre>
	./vsh.bash -start [destination]* [port] [archive_directory]*
</pre>
* To stop a server :
<pre>
	./vsh.bash -stop [destination]* [port]
</pre>

*: optional.

### Client connection

* To display the archives available on a server :
<pre>
	./vsh.bash -list [destination] [port]
</pre>
* To browse an archive :
<pre>
	./vsh.bash -browse [destination] [port] [archive_name]
</pre>
* To extract an archive on your computer :
<pre>
	./vsh.bash -extract [destination] [port] [archive_name]
</pre>

### Using browse mode

While using browse mode, there is a lot of linux-like command such as cd, ls, pwd, rm, etc.
Type help to show them all.
