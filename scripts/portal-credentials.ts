export interface PortalCredential {
  brandCode: "KILELE" | "KAROO" | "MARRAKECH";
  brandName: string;
  role: "owner" | "analyst";
  email: string;
  password: string;
}

export interface PortalCredentialFile {
  accounts: PortalCredential[];
  reportPassword: string;
}
