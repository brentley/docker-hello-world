Let's create a hello world project to dockerize
```
mkdir docker-hello-world
```

We'll start by creating our hello world app. This is the example Express app.
```
cat <<EOF >app.js
const express = require('express')
const app = express()
const port = 3000

app.get('/', (req, res) => res.send('Hello World!'))

app.listen(port, () => console.log(\`Example app listening on port \${port}!\`))
EOF
```
When we try to run this, it fails, because there is a dependency requiring the
Express npm to be installed.
```
node app.js # will fail because no express npm
```

Let's install the express npm.
```
npm init -y
npm install express --save
```

Now when we run the demo hello world app again, it should work
```
node app.js
```

While it's running, I'll open a new terminal and curl to see the output
```
curl localhost:3000
```

Okay, now let's dockerize this application!

If we think like a server administrator, building a VM, we can get pretty far along,
but still might need to optimize.

Docker images work in layers. With each instruction, we build a layer on top of all
of the other layers, making them read-only.

The first line of our docker file is our starting point. To keep things easy, we can start with
something we already might know (like centos).

```
FROM centos
```

With only this in our Dockerfile, we can build an image:
```
docker build .
```

Let's look at what happened.
```
$ docker build .
Sending build context to Docker daemon  1.927MB
Step 1/1 : FROM centos
latest: Pulling from library/centos
8ba884070f61: Pull complete
Digest: sha256:b5e66c4651870a1ad435cd75922fe2cb943c9e973a9673822d1414824a1d0475
Status: Downloaded newer image for centos:latest
 ---> 9f38484d220f
Successfully built 9f38484d220f
```

You can see that we pulled an image of CentOS, and it looks like we downloaded the "latest"
version of that image. What does latest mean?

This is where we should talk about tags for a second.

Tags are a way of associating different versions of an image with something human readable.
In this case, since we didn't ask for a specific tag, we downloaded the "latest" tag.

Let's take a look at what tags might be available:
https://hub.docker.com/_/centos

So, rather than using "latest", it's usually better to be specific about the version
of the image we want to use as our starting point. Let's add that to our Dockerfile

```
from centos:centos7.6.1810
```

Now, we can be pretty confident that we're using an updated centos, that is the
version we prefer, so how do we run our app? We have to start by copying it to
the image:
```
from centos:centos7.6.1810

COPY . .

node app.js
```

Let's look at the images we have on our system:
```
docker images
```

Remember how we talked about tagging, and how it makes images friendlier to
look at? Let's tag our image:
```
docker build -t docker-hello-world:latest .
```

Okay, how do we run our image?

```
docker run docker-hello-world:latest
```

Notice we get an error. It looks like we need to install NodeJS:
```
from centos:centos7.6.1810

RUN curl -sL https://rpm.nodesource.com/setup_10.x | bash -

RUN yum install -y nodejs

COPY . .

CMD node app.js
```

Now let's try to curl our hello world app!
```
curl localhost:3000
```

This fails, because even though, inside our container we are listening on port 3000,
we haven't set up THE CONTAINER to listen on port 3000.

Confirm with this command (on osx):
```
lsof -Pn -i4 |grep 3000
```

If we connect the host port 3000, to the container port 3000, then we should be
able to connect to our running application:
```
docker run -t -p 3000:3000 docker-hello-world:latest
```

You can also add the EXPOSE command to the Dockerfile, and then use the `-P` option
when running docker:
```
docker run -t -P docker-hello-world:latest
```

Okay, it looks like we have a good container... but is it production worthy?
Let's talk about that... first, let's look at the size of the container:
```
docker images
```

How can we make this smaller? More efficient? you see our starting point is 202MB, but we've
grown this thing to 372MB, and our app code is only
Okay, it looks like we have a good container... but is it production worthy?
Let's talk about that... first, let's look at the size of the container:
```
docker images
```

How can we make this smaller? More efficient? you see our starting point is 202MB, but we've
grown this thing to 372MB, and our app code is only 2.3MB, so how did we add so much extra stuff?

Let's look at our Dockerfile again:
```
from centos:centos7.6.1810

RUN curl -sL https://rpm.nodesource.com/setup_10.x | bash -

RUN yum install -y nodejs

COPY . .

EXPOSE 3000

CMD node app.js
```

We are really doing 3 things that have a chance to add space... the 3 RUN commands.
Remember when we talked about layers? Each one of those writes a new layer...
Ideally, we would do everything we can in a single layer, then clean up stuff we
don't need anymore...

What if we did this instead?:
```
from centos:centos7.6.1810

RUN curl -sL https://rpm.nodesource.com/setup_10.x | bash - && \
  yum install -y nodejs && \
  adduser -r nodejs && \
  rm -rvf /var/lib/rpm /var/cache/*

USER nodejs

COPY . .

EXPOSE 3000

CMD node app.js
```

Okay, this makes a huge difference. Let's talk about why:
1) we combine all of our commands into one layer, so we can add and delete and
recover the space.
2) since each container is immutable, we don't need to plan to install future
RPMs, so we can delete the RPMdb, and the yum cache (or all caches, for that matter).
3) Not a space saver, but when it comes time to copy in our application, and run it,
we should drop priviledges to a regular user, rather than root. It's just good security practice.

So with all of this optimization, we started at 202MB, and ended at 259MB. It's not bad, but
what if we could do better? What if we didn't need to start with 202MB?

There is another distro that is super popular, called Alpine Linux. It's deisgned for containers.
the starting base image is 3MB. Let's see what it takes to use that image, instead.

```
FROM alpine:3.9.4

RUN apk add -U --no-cache nodejs && \
  adduser -S nodejs

USER nodejs

COPY . .

EXPOSE 3000

CMD node app.js
```
by changing the base image, we simplify the build, and go to a final artifact of 33.5MB.

Awesome!

Okay, so now what? I can build an image. I can RUN an image, but how do I run it on other machines?

Well, first we need to put the image someplace the other machines can find it...

This is where Amazon ECR comes in to play. ECR is a special artifact store, designed to hold Docker images.
It's compatible with the docker command line tools, so it's easy to use, but will scale to meet
your needs, no matter how many images you end up pushing to it.