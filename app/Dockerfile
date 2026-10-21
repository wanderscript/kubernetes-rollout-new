FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY main.go ./
ARG TARGETOS=linux
ARG TARGETARCH=amd64
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/rollout-lab .

FROM alpine:3.22
RUN apk add --no-cache ca-certificates \
    && addgroup -S -g 10001 app \
    && adduser -S -D -H -u 10001 -G app app
COPY --from=build /out/rollout-lab /usr/local/bin/rollout-lab
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/rollout-lab"]
