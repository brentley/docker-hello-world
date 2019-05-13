from alpine:3.9.4

RUN apk add -U --no-cache nodejs && \
  adduser -S nodejs

USER nodejs

COPY . .

EXPOSE 3000

CMD node app.js

