from centos:centos7.6.1810

RUN curl -sL https://rpm.nodesource.com/setup_10.x | bash -

RUN yum install -y nodejs

COPY . .

RUN npm install

CMD node app.js
