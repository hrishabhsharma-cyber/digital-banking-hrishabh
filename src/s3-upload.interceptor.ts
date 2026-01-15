import { Injectable, NestInterceptor, ExecutionContext, CallHandler } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import multerS3 from 'multer-s3';
import { S3Client } from '@aws-sdk/client-s3';
import multer from 'multer';
import { Observable } from 'rxjs';

@Injectable()
export class S3UploadInterceptor implements NestInterceptor {
  private multerInstance: multer.Multer;

  constructor(private configService: ConfigService) {
    const accessKeyId = this.configService.get<string>('AWS_ACCESS_KEY_ID');
    const secretAccessKey = this.configService.get<string>('AWS_SECRET_ACCESS_KEY');
    const region = this.configService.get<string>('AWS_REGION', 'us-east-1');

    if (!accessKeyId || !secretAccessKey) {
      throw new Error('AWS credentials are required');
    }

    const s3 = new S3Client({
      credentials: {
        accessKeyId,
        secretAccessKey,
      },
      region,
    });

    this.multerInstance = multer({
      storage: multerS3({
        s3,
        bucket: this.configService.get('AWS_S3_BUCKET'),
        key: (req, file, cb) => {
          const uniqueName = `${Date.now()}-${Math.round(Math.random() * 1e9)}-${file.originalname}`;
          cb(null, `jiohotstar/${uniqueName}`);
        },
      }),
    });
  }

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const ctx = context.switchToHttp();
    const request = ctx.getRequest();
    const response = ctx.getResponse();

    return new Observable((observer) => {
      this.multerInstance.single('file')(request, response, (err) => {
        if (err) {
          observer.error(err);
          return;
        }
        next.handle().subscribe({
          next: (value) => observer.next(value),
          error: (error) => observer.error(error),
          complete: () => observer.complete(),
        });
      });
    });
  }
}

