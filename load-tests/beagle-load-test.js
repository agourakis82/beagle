import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<200', 'p(99)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE_URL = 'http://localhost:3000';
const TOKEN = 'your-jwt-token';

export default function () {
  const createRes = http.post(
    `${BASE_URL}/api/v1/nodes`,
    JSON.stringify({
      content: `Load test node ${__VU}-${__ITER}`,
      content_type: 'Thought',
    }),
    {
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${TOKEN}`,
      },
    },
  );

  check(createRes, {
    'status is 201': (r) => r.status === 201,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });

  const nodeId = JSON.parse(createRes.body).id;

  const getRes = http.get(`${BASE_URL}/api/v1/nodes/${nodeId}`, {
    headers: { Authorization: `Bearer ${TOKEN}` },
  });

  check(getRes, {
    'status is 200': (r) => r.status === 200,
    'response time < 100ms': (r) => r.timings.duration < 100,
  });

  sleep(1);
}








