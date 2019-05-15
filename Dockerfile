FROM alpine:3.9.4

RUN apk add -U --no-cache nodejs npm && \
  adduser -S nodejs

USER nodejs

WORKDIR /home/nodejs

COPY . .

RUN npm install

EXPOSE 3000

CMD node app.js

