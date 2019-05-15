
### Create the app

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

### Dockerize our app

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

### Let's talk tagging

This is where we should talk about tags for a second.

Tags are a way of associating different versions of an image with something human readable.
In this case, since we didn't ask for a specific tag, we downloaded the "latest" tag.

Let's take a look at what tags might be available:
https://hub.docker.com/_/centos

So, rather than using *latest*, it's usually better to be specific about the version
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
# --init spawns an init process, then launches our command using the init process
# -i launches "interactively", rather than forking into the background
docker run --init -i docker-hello-world:latest
```

Notice we get an error. It looks like we need to install NodeJS:
```
from centos:centos7.6.1810

RUN curl -sL https://rpm.nodesource.com/setup_10.x | bash -

RUN yum install -y nodejs

COPY . .

CMD node app.js
```

### Testing the app

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
docker run --init -i -p 3000:3000 docker-hello-world:latest
```

You can also add the EXPOSE command to the Dockerfile, and then use the `-P` option
when running docker. This will expose our port to a dynamic/available high port on the host:
```
docker run --init -i -P docker-hello-world:latest
```

### Uh Oh... we kinda messed up...
In our Dockerfile, we have `COPY . .` and that copies everything from the directory
into the container. Normally that okay, but in this case, we had built/installed
Express locally, which installed into `node_modules`. While this worked, it's not
great design, because I can't always count on those modules being built, or even
being current.

A better design is to actually build the modules inside the container, so we can
ensure they are built every time. Also, we should add a .dockerignore file so if
we have built modules locally, they don't accidentally get copied into the container.

```
cat <<EOF>.dockerignore
.git
.gitignore
node_modules
EOF
```
Check out the `build context` before and after... we went from sending MBs of data
to the Docker daemon, to sending KBs of data.

Now that we have excluded `node_modules` we should make sure we build the modules
inside the container.
```
from centos:centos7.6.1810

RUN curl -sL https://rpm.nodesource.com/setup_10.x | bash -

RUN yum install -y nodejs

COPY . .

RUN npm install

EXPOSE 3000

CMD node app.js
```

Let's test our change to make sure things still work as expected:
```
docker run --init -i -p 3000:3000 docker-hello-world:latest
```

### Optimizing the container

Okay, it looks like we have a good container... but is it production worthy?
Let's talk about that... first, let's look at the size of the container:
```
docker images
```

How can we make this smaller? More efficient? you see our starting point is 202MB, but we've
grown this thing to 373MB, and our app code is only

Let's look at our Dockerfile again:
```
from centos:centos7.6.1810

RUN curl -sL https://rpm.nodesource.com/setup_10.x | bash -

RUN yum install -y nodejs

COPY . .

RUN npm install

EXPOSE 3000

CMD node app.js
```

We are really doing 4 things that have a chance to add space... the 3 RUN commands,
plus the copy of our app code into the container. Remember when we talked about
layers? Each one of those writes a new layer... Ideally, we would do everything
we can in fewer layers, take advantage of layer caching, then clean up stuff we
don't need anymore...

What if we did this instead?:
```
from centos:centos7.6.1810

RUN curl -sL https://rpm.nodesource.com/setup_10.x | bash - && \
  yum install -y nodejs && \
  adduser -mr nodejs && \
  rm -rvf /var/lib/rpm /var/cache/*

USER nodejs

WORKDIR /home/nodejs

COPY . .

RUN npm install

EXPOSE 3000

CMD node app.js
```

Okay, this makes a huge difference. Let's talk about why:
- we combine all of our commands into one layer, so we can add and delete and
recover the space.
- since each container is immutable, we don't need to plan to install future
RPMs, so we can delete the RPMdb, and the yum cache (or all caches, for that matter).
- Not a space saver, but when it comes time to copy in our application, and run it,
we should drop priviledges to a regular user, rather than root. It's just good security practice.

So with all of this optimization, we started at 202MB, and ended at 260MB. It's not bad, but
what if we could do better? What if we didn't need to start with 202MB?

### Optimizing the build order to take advantage of caching

There is another optimization we can do to optimize how much work needs to be done
if we change something in the app. Watch what happens if I change a line in app.js
and then rebuilt the container.

Did you see that it had to rerun the `npm install`? This is because Docker has to
rerun every command below the first command that has a changed file. That `COPY . .`
is copying both the `package.json` file and the `app.js` file so even if all I changed
was the `app.js` file it has to rerun the NPM install.

We can optimize it like this:

```
from centos:centos7.6.1810

RUN curl -sL https://rpm.nodesource.com/setup_10.x | bash - && \
  yum install -y nodejs && \
  adduser -mr nodejs && \
  rm -rvf /var/lib/rpm /var/cache/*

USER nodejs

WORKDIR /home/nodejs

ADD package.json .

RUN npm install

ADD app.js

EXPOSE 3000

CMD node app.js
```

Now if I run this build I get an extra layer, but this layer lets Docker cache the
package.json and the installed dendencies separately from the app code. And
if I change a line in the `app.js` file and rerun the build you'll see that it is
able to skip the NPM install because nothing has changed in `package.json`

This is a huge boost to speed and productivity when working with Docker containers

### Use a container specific distribution

There is another distro that is super popular, called Alpine Linux. It's deisgned for containers.
the starting base image is 3MB. Let's see what it takes to use that image, instead.

```
FROM alpine:3.9.4

RUN apk add -U --no-cache nodejs npm && \
  adduser -S nodejs

USER nodejs

WORKDIR /home/nodejs

COPY . .

RUN npm install

EXPOSE 3000

CMD node app.js

```
by changing the base image, we simplify the build, and go to a final artifact of 49MB.

Awesome!

### Pushing to Amazon ECR

Okay, so now what? I can build an image. I can RUN an image, but how do I run it on other machines?

Well, first we need to put the image someplace the other machines can find it...

This is where Amazon ECR comes in to play. ECR is a special artifact store, designed to hold Docker images.
It's compatible with the docker command line tools, so it's easy to use, but will scale to meet
your needs, without worrying about how many containers you push, or how many clients
might pull from it.

We'll start by creating a repository in ECR, and following the `push commands`.



```
$(aws ecr get-login --no-include-email --region us-east-1)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) # this is setting my account ID as a variable
docker push ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/docker-hello-world:latest
```

### Pulling from Amazon ECR to a centos server
Now that we've pushed to our artifact store, we can go to a fresh server, pull the
image and run it, but first we need to install docker.
```
sudo -i
yum -y install docker
systemctl start docker.service
systemctl enable docker.service

$(aws ecr get-login --no-include-email --region us-east-1)
```
If this is all we do, we should get an error when trying to log in to ECR.

This is because we haven't assigned permission to allow ECR usage
yet. Let's do that now by creating a Read Only IAM role, then assigning it to
the EC2 instance.

In reality, the permission we used would likely be merged in to your existing EC2
instance role, but I'm not using one right now, so I'll create one that can be
used on any of my instances.

Once we have the IAM role attached, let's test ECR access again:
```
$(aws ecr get-login --no-include-email --region us-east-1)
```

This time, we should be logged in.

Next, let's try to pull our image:
```
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) # this is setting my account ID as a variable
docker pull ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/docker-hello-world:latest
```

Just to validate our ECR permissions, let's attempt to push to the registry...
With our Read Only permission, this should fail:
```
docker push ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/docker-hello-world:latest
```

Now let's see if this server has nodejs installed already:
```
which node 2>/dev/null || echo "nodejs is not installed"
which npm 2> /dev/null || echo "npm is not installed"
```

So there is no nodejs installed and no npm command either.

### Running our code on a really stripped down server that doesn't have nodejs
```
docker run --init -i -p 3000:3000 ${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/docker-hello-world:latest
```

We can test in another shell, and see our app does indeed work! Also, we can verify
it's not running as root, and is just another process on our OS.
